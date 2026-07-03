# Chat ↔ Editor ↔ DB Sync Loop — Design

**Date:** 2026-07-03
**Status:** Approved
**Goal:** Make one loop work reliably: build a workflow via AI chat, edit it manually in
the visual editor, and have the chat see those manual edits on the next message — with
everything persisted to the database. Flow *running* is explicitly out of scope
(second priority).

## Background

The foundations already exist and work:

- Chat API (`POST /api/v1/chat`, SSE) with persisted conversations/messages
  (`lib/kalcifer_web/controllers/chat_controller.ex`, `lib/kalcifer/ai/context.ex`)
- 13 AI tools including `create_flow`, `add_node`, `modify_node`, `remove_node`,
  `get_flow_graph` (`lib/kalcifer/ai/tools.ex`)
- Conversation ↔ flow linking via `entity_type`/`entity_id`; `create_flow` is
  idempotent per conversation
- Manual editing: `PUT /api/v1/flows/:flow_id/versions/:version_number`
  (`Flows.update_version/3` updates a draft in place; editing a published version
  creates a new draft)
- React frontend: `ChatPanel.tsx` (SSE consumer), `FlowEditorInline.tsx` (visual editor)

**The gap:** the AI's context never includes the current graph. The system prompt
(`ChatController.build_system_prompt/1`) only loads operator memory, so the AI reasons
from stale tool results in conversation history. Manual edits are invisible to the chat.
In the reverse direction, `FlowEditorInline` loads the graph only on mount, so AI edits
are invisible to an open editor.

## Design

### 1. Backend — graph snapshot injected into system prompt (core change)

On every `POST /chat` request, if the conversation is linked to a flow
(`entity_type: "flow"`):

1. Load the flow and its current working version — the latest draft, or the latest
   version if no draft exists (reuse the same resolution the AI tools use).
2. Render a compact text snapshot: flow name / id / status, version number and status,
   node list (id, type, short config summary), edges (`source → target [branch]`).
3. Append it to the system prompt with an explicit note: *"This is the flow's current
   state — the operator may have edited it manually since the last message. Trust this
   over anything earlier in the conversation."*

Injection point: `build_system_prompt` in
`lib/kalcifer_web/controllers/chat_controller.ex` (gains a `conversation_id` argument).
Both execution paths (engine agent-flow and direct `chat_with_tools` fallback) receive
this system prompt, so one injection point covers both.

Also fixes an existing quirk: today `build_system_prompt` returns `nil` when there are
no memories, dropping the default system prompt entirely. New composition:
**base prompt + memory block (if any) + graph snapshot (if any)**.

Safety:
- Snapshot has a size cap — long config values truncated; above a node-count threshold,
  configs are omitted (ids/types/edges kept) with a note telling the AI to call
  `get_flow_graph` for full detail.
- Any failure loading the snapshot degrades gracefully to no snapshot; chat never
  breaks because of it.

### 2. Backend — mutating tool results return resulting graph state

`add_node` / `modify_node` / `remove_node` results include the updated draft's brief
state (node/edge counts + node id/type list) so the AI knows the exact result within
the same message turn. (Verify what they return today; extend only if missing.)

### 3. Frontend — editor refresh on AI edits

- `ChatPanel`: on `tool_done` for a graph-mutating tool (`create_flow`, `add_node`,
  `modify_node`, `remove_node`) → invoke new `onFlowMutated(flowId)` callback.
- `FlowEditorInline` gains a `refreshToken` prop (bumped by the parent on mutation):
  - If there are no unsaved local changes (`hasChanges === false`) → automatically
    re-fetch flow + versions.
  - If there are unsaved changes → show a banner ("AI updated the graph — reload")
    with a reload button, so the operator's local edits are never silently clobbered.
- Wiring goes through the existing parent chain (`WorkPage` → `RightPanel`/context
  panel → `FlowEditorInline`), following the existing `onContextContent` pattern.

### 4. Persistence — already works; pin with tests

`Flows.update_version/3` updates drafts in place and forks published versions into new
drafts. AI tools re-read the draft from the DB on every call, so AI writes never
clobber manual edits at the storage layer. Add an integration test covering the full
loop: create flow via tool → manual `PUT` with modified graph → next chat turn's
system prompt contains the updated graph.

## Explicitly out of scope (YAGNI)

- Conflict detection / optimistic locking (single operator; last-write-wins is fine)
- Audit trail of manual edits in conversation history
- WebSocket push to the editor (SSE `tool_done` is a sufficient signal)
- Flow running/execution improvements (second priority)

## Testing

- **Unit (backend):** snapshot renderer — normal graph, oversized graph (cap), no
  linked flow, missing version, load failure.
- **Integration (backend):** chat request for a linked conversation includes the
  current draft graph in the system prompt after a manual `PUT` update; system prompt
  composition with/without memories.
- **Frontend:** `ChatPanel` fires `onFlowMutated` on mutating `tool_done`;
  `FlowEditorInline` auto-refreshes without local changes and shows the banner with
  local changes.

## Error handling

- Snapshot build failures are logged and skipped — never fail the chat request.
- Editor re-fetch failures keep the current view and surface the existing error state.
