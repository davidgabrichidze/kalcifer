# Chat ↔ Editor ↔ DB Sync Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat↔editor loop reliable: the AI sees the current flow graph (including manual edits) on every chat message, and the visual editor refreshes when the AI edits the graph.

**Architecture:** Two new focused backend modules — `Kalcifer.AI.FlowSnapshot` (renders a compact text snapshot of a conversation's linked flow) and `Kalcifer.AI.SystemPrompt` (composes base prompt + memory + snapshot, replacing `ChatController.build_system_prompt/1`). Mutating AI tools return the resulting graph summary. On the frontend, `ChatPanel` reports graph-mutating tool completions upward; `WorkPage` bumps a `refreshToken` that makes `FlowEditorInline` re-fetch (or show a stale banner when the operator has unsaved local edits). Also fixes `FlowEditorInline` picking the *oldest* version instead of the current working draft.

**Tech Stack:** Elixir/Phoenix (backend), React + TypeScript + Vitest (frontend/), ExMachina factories, `Kalcifer.DataCase` for DB tests.

**Spec:** `docs/superpowers/specs/2026-07-03-chat-editor-sync-design.md`

## Global Constraints

- Always run backend tests with `--trace`: `mix test <path> --trace`
- Credo strict: aliases alphabetically ordered, max line length 120, no `@doc` on private functions (use plain `#` comments)
- Frontend tests: `cd frontend && npx vitest run <path>`
- User-facing frontend copy is in Georgian
- Snapshot failures must never break the chat request (degrade to no snapshot)
- Node modules / registry names: snake_case strings (`"event_entry"`, `"wait"`, `"exit"`)
- Commit format: `<type>(<scope>/<subscope>): <description>` (e.g. `feat(ai/prompts): …`, `feat(fe/editor): …`)

---

### Task 1: `Kalcifer.AI.FlowSnapshot` — compact graph snapshot renderer

**Files:**
- Create: `lib/kalcifer/ai/flow_snapshot.ex`
- Test: `test/kalcifer/ai/flow_snapshot_test.exs`

**Interfaces:**
- Consumes: `Kalcifer.AI.Context.get_conversation/1` (returns `%Conversation{entity_type, entity_id}` or nil), `Kalcifer.Flows.get_flow/1`, `Kalcifer.Flows.list_versions/1` (ascending by `version_number`)
- Produces: `FlowSnapshot.for_conversation(conversation_id :: String.t() | nil) :: String.t() | nil` — used by Task 2. Returns nil when there is no linked flow, no versions, or any load failure.

- [ ] **Step 1: Write the failing test**

Create `test/kalcifer/ai/flow_snapshot_test.exs`:

```elixir
defmodule Kalcifer.AI.FlowSnapshotTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.{Context, FlowSnapshot}

  import Kalcifer.Factory

  defp conversation_linked_to(flow) do
    {:ok, conv} = Context.create_conversation(flow.tenant_id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)
    conv
  end

  test "returns nil for nil conversation id" do
    assert FlowSnapshot.for_conversation(nil) == nil
  end

  test "returns nil when conversation has no linked flow" do
    tenant = insert(:tenant)
    {:ok, conv} = Context.create_conversation(tenant.id)

    assert FlowSnapshot.for_conversation(conv.id) == nil
  end

  test "returns nil when the linked flow has no versions" do
    flow = insert(:flow)
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(conv.id) == nil
  end

  test "renders flow name, version, nodes and edges for a linked draft flow" do
    flow = insert(:flow, name: "Onboarding")
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(conv.id)

    assert snapshot =~ "Onboarding"
    assert snapshot =~ "Version: 1 (draft)"
    assert snapshot =~ "entry_1 (event_entry)"
    assert snapshot =~ "entry_1 → exit_1"
  end

  test "prefers the latest draft over an older published version" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "published")
    insert(:flow_version, flow: flow, version_number: 2, status: "draft")
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(conv.id) =~ "Version: 2 (draft)"
  end

  test "falls back to the latest version when no draft exists" do
    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "published")
    insert(:flow_version, flow: flow, version_number: 2, status: "published")
    conv = conversation_linked_to(flow)

    assert FlowSnapshot.for_conversation(conv.id) =~ "Version: 2 (published)"
  end

  test "truncates long config values" do
    long_value = String.duplicate("x", 500)

    graph = %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => long_value}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [%{"source" => "entry_1", "target" => "exit_1"}]
    }

    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(conv.id)

    refute snapshot =~ long_value
    assert snapshot =~ "…"
  end

  test "omits configs above the node-count threshold and points at get_flow_graph" do
    nodes =
      for i <- 1..35 do
        %{"id" => "n#{i}", "type" => "wait", "config" => %{"duration" => "1d"}}
      end

    graph = %{"nodes" => nodes, "edges" => []}

    flow = insert(:flow)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft", graph: graph)
    conv = conversation_linked_to(flow)

    snapshot = FlowSnapshot.for_conversation(conv.id)

    assert snapshot =~ "n1 (wait)"
    refute snapshot =~ "duration"
    assert snapshot =~ "get_flow_graph"
  end
end
```

Note: ExMachina `insert/2` writes structs directly (no changeset validation), so arbitrary graphs are fine in tests.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/kalcifer/ai/flow_snapshot_test.exs --trace`
Expected: FAIL — `module Kalcifer.AI.FlowSnapshot is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/kalcifer/ai/flow_snapshot.ex`:

```elixir
defmodule Kalcifer.AI.FlowSnapshot do
  @moduledoc """
  Renders a compact text snapshot of a conversation's linked flow graph for
  injection into the AI system prompt. Read-only — never creates versions.

  Returns nil when the conversation has no linked flow, the flow or its
  versions are missing, or anything fails to load — the chat must keep
  working without a snapshot.
  """

  alias Kalcifer.AI.Context
  alias Kalcifer.Flows

  # Per-node config JSON longer than this gets truncated.
  @max_config_chars 200
  # Above this many nodes, configs are omitted entirely (ids/types/edges kept).
  @config_node_limit 30

  @spec for_conversation(String.t() | nil) :: String.t() | nil
  def for_conversation(nil), do: nil

  def for_conversation(conversation_id) do
    with %{entity_type: "flow", entity_id: flow_id} when not is_nil(flow_id) <-
           Context.get_conversation(conversation_id),
         %{} = flow <- Flows.get_flow(flow_id),
         %{} = version <- current_working_version(flow.id) do
      render(flow, version)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # The version the AI and the editor both work on: the latest draft,
  # or the latest version of any status when no draft exists.
  defp current_working_version(flow_id) do
    versions = Flows.list_versions(flow_id)

    case Enum.filter(versions, &(&1.status == "draft")) do
      [] -> List.last(versions)
      drafts -> Enum.max_by(drafts, & &1.version_number)
    end
  end

  defp render(flow, version) do
    graph = version.graph || %{"nodes" => [], "edges" => []}
    nodes = Map.get(graph, "nodes", [])
    edges = Map.get(graph, "edges", [])
    include_configs? = length(nodes) <= @config_node_limit

    config_note =
      if include_configs? do
        ""
      else
        "\n(config-ები არ არის ნაჩვენები — დეტალებისთვის გამოიყენე get_flow_graph)"
      end

    """

    ## მიმდინარე ფლოუ — მდგომარეობა ბაზაში

    Flow: #{flow.name} (id: #{flow.id}, status: #{flow.status})
    Version: #{version.version_number} (#{version.status})
    Nodes (#{length(nodes)}):
    #{render_nodes(nodes, include_configs?)}
    Edges (#{length(edges)}):
    #{render_edges(edges)}#{config_note}

    ეს არის გრაფის მიმდინარე მდგომარეობა — შესაძლოა ოპერატორმა ხელით შეცვალა
    წინა მესიჯის შემდეგ. ენდე ამ სექციას და არა საუბრის ისტორიაში არსებულ
    ძველ ვერსიებს.
    """
  end

  defp render_nodes([], _include_configs?), do: "  (ცარიელი)"

  defp render_nodes(nodes, include_configs?) do
    Enum.map_join(nodes, "\n", fn node ->
      base = "  - #{node["id"]} (#{node["type"]})"
      config = node["config"] || %{}

      if include_configs? and config != %{} do
        base <> " config: " <> truncate(Jason.encode!(config))
      else
        base
      end
    end)
  end

  defp render_edges([]), do: "  (ცარიელი)"

  defp render_edges(edges) do
    Enum.map_join(edges, "\n", fn edge ->
      base = "  - #{edge["source"]} → #{edge["target"]}"
      if edge["branch"], do: base <> " [branch: #{edge["branch"]}]", else: base
    end)
  end

  defp truncate(str) when byte_size(str) > @max_config_chars do
    String.slice(str, 0, @max_config_chars) <> "…"
  end

  defp truncate(str), do: str
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/kalcifer/ai/flow_snapshot_test.exs --trace`
Expected: PASS (8 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/kalcifer/ai/flow_snapshot.ex test/kalcifer/ai/flow_snapshot_test.exs
git commit -m "feat(ai/prompts): add flow graph snapshot renderer

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `Kalcifer.AI.SystemPrompt` + ChatController wiring

**Files:**
- Create: `lib/kalcifer/ai/system_prompt.ex`
- Modify: `lib/kalcifer_web/controllers/chat_controller.ex` (alias block at line 4; `create/2` around line 61; `run_direct_chat/5` around line 225; delete `build_system_prompt/1` at lines 267–291)
- Test: `test/kalcifer/ai/system_prompt_test.exs`
- Test (modify): `test/kalcifer_web/controllers/chat_controller_test.exs` (append one test)

**Interfaces:**
- Consumes: `FlowSnapshot.for_conversation/1` (Task 1), `Kalcifer.AI.Client.default_system_prompt/0`, `Kalcifer.AI.Context.recall_all/1`
- Produces: `SystemPrompt.build(tenant_id :: String.t(), conversation_id :: String.t() | nil) :: String.t()` — always returns a non-empty binary (base prompt at minimum). ChatController uses it for both the engine path and the direct-chat fallback.

- [ ] **Step 1: Write the failing test**

Create `test/kalcifer/ai/system_prompt_test.exs`:

```elixir
defmodule Kalcifer.AI.SystemPromptTest do
  use Kalcifer.DataCase, async: true

  alias Kalcifer.AI.{Context, SystemPrompt}
  alias Kalcifer.Flows

  import Kalcifer.Factory

  test "returns the base prompt when there is no memory and no linked flow" do
    tenant = insert(:tenant)
    {:ok, conv} = Context.create_conversation(tenant.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "კალციფერი"
  end

  test "returns the base prompt for a nil conversation id" do
    tenant = insert(:tenant)

    assert SystemPrompt.build(tenant.id, nil) =~ "კალციფერი"
  end

  test "includes operator memory when present" do
    tenant = insert(:tenant)
    {:ok, _} = Context.remember(tenant.id, "brand_voice", "playful", "preference")
    {:ok, conv} = Context.create_conversation(tenant.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "brand_voice: playful"
  end

  test "includes the linked flow snapshot" do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant, name: "Onboarding")
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    {:ok, conv} = Context.create_conversation(tenant.id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "Onboarding"
    assert prompt =~ "entry_1 (event_entry)"
  end

  test "reflects manual graph edits on the next build (the sync loop)" do
    tenant = insert(:tenant)
    flow = insert(:flow, tenant: tenant)
    insert(:flow_version, flow: flow, version_number: 1, status: "draft")
    {:ok, conv} = Context.create_conversation(tenant.id)
    {:ok, conv} = Context.link_entity(conv, "flow", flow.id)

    # Simulate the operator saving from the visual editor
    # (same path as PUT /api/v1/flows/:flow_id/versions/:version_number).
    edited_graph = %{
      "nodes" => [
        %{"id" => "entry_1", "type" => "event_entry", "config" => %{"event_type" => "signed_up"}},
        %{"id" => "manual_wait_1", "type" => "wait", "config" => %{"duration" => "1d"}},
        %{"id" => "exit_1", "type" => "exit", "config" => %{}}
      ],
      "edges" => [
        %{"source" => "entry_1", "target" => "manual_wait_1"},
        %{"source" => "manual_wait_1", "target" => "exit_1"}
      ]
    }

    {:ok, _} = Flows.update_version(flow, 1, %{graph: edited_graph, changelog: "manual edit"})

    prompt = SystemPrompt.build(tenant.id, conv.id)

    assert prompt =~ "manual_wait_1"
  end
end
```

If `Flows.update_version` returns a changeset error about the `wait` node's required config, inspect the registered schema (`Kalcifer.Engine.Nodes.Wait` category modules) and adjust the `"config"` keys to satisfy it — the test's point is the prompt reflecting the edit, not the specific node type.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/kalcifer/ai/system_prompt_test.exs --trace`
Expected: FAIL — `module Kalcifer.AI.SystemPrompt is not available`

- [ ] **Step 3: Write the module**

Create `lib/kalcifer/ai/system_prompt.ex`:

```elixir
defmodule Kalcifer.AI.SystemPrompt do
  @moduledoc """
  Composes the chat system prompt: base personality prompt + operator memory
  + current linked-flow snapshot. Always returns a binary, so callers never
  need nil-handling (previously the prompt was dropped entirely when the
  operator had no memories).
  """

  alias Kalcifer.AI.{Client, Context, FlowSnapshot}

  @spec build(String.t(), String.t() | nil) :: String.t()
  def build(tenant_id, conversation_id) do
    [
      Client.default_system_prompt(),
      memory_block(tenant_id),
      FlowSnapshot.for_conversation(conversation_id)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp memory_block(tenant_id) do
    memories = Context.recall_all(tenant_id)

    if Enum.empty?(memories) do
      nil
    else
      lines = Enum.map_join(memories, "\n", fn m -> "- #{m.key}: #{m.value}" end)

      """

      ## რაც მახსოვს ამ მომხმარებლის შესახებ:
      #{lines}

      გამოიყენე ეს ინფორმაცია საუბარში ბუნებრივად — ნუ ჩამოთვლი რა გახსოვს,
      უბრალოდ იცოდე და გაითვალისწინე.
      """
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/kalcifer/ai/system_prompt_test.exs --trace`
Expected: PASS (5 tests, 0 failures)

- [ ] **Step 5: Wire into ChatController**

In `lib/kalcifer_web/controllers/chat_controller.ex`:

1. Update the alias (line 4) — keep alphabetical order:

```elixir
alias Kalcifer.AI.{AgentFlows, Client, Context, SystemPrompt, Tools}
```

2. In `create/2`, replace:

```elixir
    # Load operator memory into system prompt
    system_prompt = build_system_prompt(tenant_id)
```

with:

```elixir
    # Base prompt + operator memory + current linked-flow graph snapshot
    system_prompt = SystemPrompt.build(tenant_id, conversation_id)
```

3. In `run_direct_chat/5`, replace:

```elixir
    opts = if system_prompt, do: [system: system_prompt], else: []
    opts = opts ++ tenant_ai_opts(tenant_id)
```

with:

```elixir
    opts = [system: system_prompt] ++ tenant_ai_opts(tenant_id)
```

4. Delete the entire `build_system_prompt/1` private function and its
   `# ── System prompt with memory ──…` section comment (lines 267–291).

`Client` remains aliased — it is still used for `Client.chat_with_tools/5`.

- [ ] **Step 6: Add a controller regression test**

Append to `test/kalcifer_web/controllers/chat_controller_test.exs` (inside the module, after the existing describes; it already has `import Kalcifer.Factory` and the `ensure_demo_tenant/0` helper):

```elixir
  # ── Linked-flow snapshot injection ────────────────────────────

  describe "linked-flow snapshot" do
    test "chat with a flow-linked conversation still streams SSE", %{conn: conn} do
      tenant = ensure_demo_tenant()
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      {:ok, conversation} = Context.create_conversation(tenant.id)
      {:ok, conversation} = Context.link_entity(conversation, "flow", flow.id)

      conn =
        post(conn, "/api/v1/chat", %{
          "messages" => [%{"role" => "user", "content" => "რა მდგომარეობაშია ფლოუ?"}],
          "conversation_id" => conversation.id
        })

      assert conn.status == 200
      assert {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
      assert String.contains?(ct, "text/event-stream")
    end
  end
```

Note: pass the existing tenant struct as the association (`tenant: tenant`), not `tenant_id:` — the flow factory declares `tenant: build(:tenant)`, and an inserted-struct association override wins over a raw FK override in ExMachina.

- [ ] **Step 7: Run the affected suites**

Run: `mix test test/kalcifer/ai/system_prompt_test.exs test/kalcifer_web/controllers/chat_controller_test.exs --trace`
Expected: PASS, 0 failures

- [ ] **Step 8: Commit**

```bash
git add lib/kalcifer/ai/system_prompt.ex lib/kalcifer_web/controllers/chat_controller.ex \
  test/kalcifer/ai/system_prompt_test.exs test/kalcifer_web/controllers/chat_controller_test.exs
git commit -m "feat(ai/prompts): inject linked-flow snapshot into chat system prompt

The AI now sees the current draft graph (including manual editor saves)
on every message instead of relying on stale tool results in history.
Also fixes the base system prompt being dropped when no memories exist.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Mutating tool results return the resulting graph summary

**Files:**
- Modify: `lib/kalcifer/ai/tools.ex` (`do_execute("add_node", …)` at ~line 718, `do_execute("modify_node", …)` at ~line 789, `do_execute("remove_node", …)` at ~line 830; new private helper near `get_or_create_draft_version/1` at ~line 1161)
- Test: `test/kalcifer/ai/tools_test.exs` (append a describe block)

**Interfaces:**
- Consumes: existing `Tools.execute/4` (`Tools.execute(name, input, tenant_id, ctx)` returning `{:ok, json_string} | {:error, reason}`)
- Produces: `add_node`/`modify_node`/`remove_node` result JSON always contains `"total_nodes"`, `"total_edges"`, and `"current_nodes"` (list of `%{"id" => …, "type" => …}`), reflecting the graph *after* the mutation.

- [ ] **Step 1: Write the failing test**

Append to `test/kalcifer/ai/tools_test.exs` (check the top of the file for existing aliases/imports — it already imports the factory; reuse its setup conventions):

```elixir
  describe "mutating tool results include graph summary" do
    setup do
      tenant = insert(:tenant)
      flow = insert(:flow, tenant: tenant)
      insert(:flow_version, flow: flow, version_number: 1, status: "draft")
      %{tenant: tenant, flow: flow}
    end

    test "modify_node returns total counts and current node list", %{tenant: tenant, flow: flow} do
      {:ok, result} =
        Tools.execute(
          "modify_node",
          %{"flow_id" => flow.id, "node_id" => "entry_1", "config" => %{"event_type" => "clicked"}},
          tenant.id
        )

      decoded = Jason.decode!(result)

      assert decoded["total_nodes"] == 2
      assert decoded["total_edges"] == 1

      assert %{"id" => "entry_1", "type" => "event_entry"} in decoded["current_nodes"]
    end

    test "remove_node returns total counts and current node list", %{tenant: tenant, flow: flow} do
      {:ok, result} =
        Tools.execute(
          "remove_node",
          %{"flow_id" => flow.id, "node_id" => "exit_1"},
          tenant.id
        )

      decoded = Jason.decode!(result)

      assert decoded["total_nodes"] == 1
      assert decoded["total_edges"] == 0
      assert decoded["current_nodes"] == [%{"id" => "entry_1", "type" => "event_entry"}]
    end

    test "add_node returns total counts and current node list", %{tenant: tenant, flow: flow} do
      {:ok, result} =
        Tools.execute(
          "add_node",
          %{
            "flow_id" => flow.id,
            "node" => %{"id" => "wait_1", "type" => "wait", "config" => %{"duration" => "1d"}},
            "edges" => [%{"source" => "entry_1", "target" => "wait_1"}]
          },
          tenant.id
        )

      decoded = Jason.decode!(result)

      assert decoded["total_nodes"] == 3
      assert decoded["total_edges"] == 2
      assert Enum.count(decoded["current_nodes"]) == 3
    end
  end
```

If the existing tests in this file use a different setup pattern (e.g. a shared `setup` at the module level creating a tenant), follow that pattern instead — the assertions are what matter.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/kalcifer/ai/tools_test.exs --trace`
Expected: FAIL — the two new `modify_node`/`remove_node` tests fail (`total_edges`/`current_nodes` are nil); `add_node` may pass `total_nodes` but fail `total_edges`.

- [ ] **Step 3: Implement the shared summary helper and use it**

In `lib/kalcifer/ai/tools.ex`, add near `get_or_create_draft_version/1` (~line 1161):

```elixir
  # Post-mutation graph state, merged into mutating tool results so the AI
  # always knows the exact resulting structure without a follow-up fetch.
  defp graph_summary(graph) do
    nodes = Map.get(graph, "nodes", [])
    edges = Map.get(graph, "edges", [])

    %{
      total_nodes: length(nodes),
      total_edges: length(edges),
      current_nodes: Enum.map(nodes, fn n -> %{id: n["id"], type: n["type"]} end)
    }
  end
```

In `do_execute("add_node", …)`: delete the `all_node_ids` computation block (the `# Include current node list so AI knows full state` comment and the following `all_node_ids = …` assignment) and replace the `result` map with:

```elixir
        result =
          %{
            flow_id: flow_id,
            added_node: node_map["id"],
            added_edges: length(edge_maps),
            version_number: version.version_number,
            validation_warnings: warnings
          }
          |> Map.merge(graph_summary(updated_graph))
```

In `do_execute("modify_node", …)` replace the `result` map with:

```elixir
          result =
            %{
              flow_id: flow_id,
              modified_node: node_id,
              node_type: old_node["type"],
              version_number: version.version_number
            }
            |> Map.merge(graph_summary(updated_graph))
```

In `do_execute("remove_node", …)` replace the `result` map with:

```elixir
        result =
          %{
            flow_id: flow_id,
            removed_node: node_id,
            removed_edges: length(edges) - length(updated_edges),
            version_number: version.version_number
          }
          |> Map.merge(graph_summary(updated_graph))
```

(The old `total_nodes:` keys are removed — `graph_summary/1` now provides them.)

- [ ] **Step 4: Run the tools suite**

Run: `mix test test/kalcifer/ai/tools_test.exs --trace`
Expected: PASS, 0 failures (including all pre-existing tests — if a pre-existing test asserted on the old `current_nodes` shape of `add_node`, update it to the new shared shape)

- [ ] **Step 5: Commit**

```bash
git add lib/kalcifer/ai/tools.ex test/kalcifer/ai/tools_test.exs
git commit -m "feat(ai/tools): return post-mutation graph summary from node tools

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `ChatPanel` reports graph mutations upward

**Files:**
- Modify: `frontend/src/components/ChatPanel.tsx` (props interface at line 18, destructuring at line 33, `detectFlowGraph` body at line 231)
- Test: `frontend/src/components/ChatPanel.test.tsx` (append tests)

**Interfaces:**
- Consumes: existing `detectFlowGraph(tool, result)` call sites in both `onToolDone` handlers (lines 208 and 340) — no call-site changes needed.
- Produces: new optional prop `onFlowMutated?: (flowId: string) => void`, fired when a `tool_done` arrives for `create_flow`, `add_node`, `modify_node`, or `remove_node` with a parseable flow id. Task 6 wires it in `WorkPage`.

- [ ] **Step 1: Write the failing test**

Append to `frontend/src/components/ChatPanel.test.tsx`. The existing top-of-file `vi.mock('../lib/api', …)` factory is static — the new tests need per-test control of the stream, so use `vi.mocked` to override per test:

```tsx
import { streamChat } from '../lib/api'

describe('ChatPanel — flow mutation notifications', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  function streamWithToolDone(tool: string, result: unknown) {
    vi.mocked(streamChat).mockImplementation((_messages, callbacks) => {
      setTimeout(() => {
        callbacks.onToolDone?.(tool, JSON.stringify(result))
        callbacks.onDone?.('done')
      }, 10)
      return { abort: vi.fn() }
    })
  }

  async function sendMessage() {
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')
    fireEvent.change(textarea, { target: { value: 'დაამატე ნაბიჯი' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })
  }

  it('fires onFlowMutated when add_node completes', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('add_node', { flow_id: 'flow-42', added_node: 'wait_1' })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    await waitFor(() => {
      expect(onFlowMutated).toHaveBeenCalledWith('flow-42')
    })
  })

  it('fires onFlowMutated with the new flow id when create_flow completes', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('create_flow', { id: 'flow-77', name: 'ახალი', graph: { nodes: [], edges: [] } })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    await waitFor(() => {
      expect(onFlowMutated).toHaveBeenCalledWith('flow-77')
    })
  })

  it('does not fire onFlowMutated for read-only tools', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('get_flow_graph', { flow_id: 'flow-42', nodes: [], edges: [] })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    await waitFor(() => {
      expect(screen.getByText(/done/)).toBeInTheDocument()
    })
    expect(onFlowMutated).not.toHaveBeenCalled()
  })
})
```

Adjust the exact callback names (`onToolDone`, `onDone`) to match the callbacks object used by `streamChat` in `ChatPanel.tsx` — read the existing mock at the top of the test file and the `streamChat` call in the component and keep them consistent.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run src/components/ChatPanel.test.tsx`
Expected: FAIL — the two "fires onFlowMutated" tests fail (`onFlowMutated` never called)

- [ ] **Step 3: Implement**

In `frontend/src/components/ChatPanel.tsx`:

1. Add to `ChatPanelProps` (line 18–31):

```tsx
  /** Called when the AI mutates a flow graph via a tool call */
  onFlowMutated?: (flowId: string) => void
```

2. Add `onFlowMutated,` to the destructured props (line 33–43).

3. In `detectFlowGraph` (line 231), after `const parsed = JSON.parse(result)`, add:

```tsx
      // Notify parent that the AI changed the graph so the editor can refresh
      const MUTATING_TOOLS = ['create_flow', 'add_node', 'modify_node', 'remove_node']
      const mutatedFlowId = tool === 'create_flow' ? parsed.id : parsed.flow_id
      if (MUTATING_TOOLS.includes(tool) && mutatedFlowId) {
        onFlowMutated?.(mutatedFlowId)
      }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run src/components/ChatPanel.test.tsx`
Expected: PASS (all tests, including pre-existing)

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/ChatPanel.tsx frontend/src/components/ChatPanel.test.tsx
git commit -m "feat(fe/chat): notify parent when AI mutates the flow graph

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `FlowEditorInline` — working-version fix, refresh token, stale banner

**Files:**
- Modify: `frontend/src/components/FlowEditorInline.tsx` (props at line 33; load effect at lines 114–137; `handleGraphChange` at line 150; `saveGraph` at line 212; canvas area JSX at ~line 493)
- Modify: `frontend/src/components/flow-editor-inline.css` (append banner styles)
- Test: `frontend/src/components/FlowEditorInline.test.tsx`

**Interfaces:**
- Consumes: nothing new from other tasks (independent of Task 4 until wired in Task 6).
- Produces: new optional prop `refreshToken?: number`. Behavior contract for Task 6: parent bumps the number → editor re-fetches if the operator has no unsaved edits, otherwise shows a stale banner with an explicit reload button. Also: the editor now loads the **latest draft** (or latest version when no draft) instead of `versions[0]` (which is the *oldest* version — the backend returns ascending order).

- [ ] **Step 1: Write the failing tests**

In `frontend/src/components/FlowEditorInline.test.tsx`:

1. Replace the existing `FlowCanvas` mock with one that can simulate a local edit:

```tsx
vi.mock('./FlowCanvas', () => ({
  default: ({
    flowGraph,
    onGraphChange,
  }: {
    flowGraph: { nodes: unknown[] } | null
    onGraphChange?: (nodes: unknown[], edges: unknown[]) => void
  }) => (
    <div data-testid="flow-canvas">
      <button data-testid="simulate-local-edit" onClick={() => onGraphChange?.([{ id: 'n1' }], [])}>
        edit
      </button>
      {flowGraph ? `${flowGraph.nodes.length} nodes` : 'no graph'}
    </div>
  ),
}))
```

2. Append the new tests:

```tsx
import { fetchFlow, fetchFlowVersions } from '../lib/api'

describe('FlowEditorInline — version selection and refresh', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('loads the latest draft version, not the oldest version', async () => {
    vi.mocked(fetchFlowVersions).mockResolvedValueOnce([
      {
        id: 'ver-1',
        version_number: 1,
        status: 'published',
        graph: { nodes: [{ id: 'a', type: 'exit', position: { x: 0, y: 0 }, config: {} }], edges: [] },
      },
      {
        id: 'ver-2',
        version_number: 2,
        status: 'draft',
        graph: {
          nodes: [
            { id: 'a', type: 'event_entry', position: { x: 0, y: 0 }, config: {} },
            { id: 'b', type: 'wait', position: { x: 100, y: 0 }, config: {} },
            { id: 'c', type: 'exit', position: { x: 200, y: 0 }, config: {} },
          ],
          edges: [],
        },
      },
    ] as never)

    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByText('3 nodes')).toBeInTheDocument()
    })
  })

  it('re-fetches when refreshToken changes and there are no local edits', async () => {
    const { rerender } = render(<FlowEditorInline flowId="flow-123" refreshToken={0} />)

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(1)
    })

    rerender(<FlowEditorInline flowId="flow-123" refreshToken={1} />)

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(2)
    })
  })

  it('shows a stale banner instead of clobbering unsaved local edits', async () => {
    const { rerender } = render(<FlowEditorInline flowId="flow-123" refreshToken={0} />)

    await waitFor(() => {
      expect(screen.getByTestId('flow-canvas')).toBeInTheDocument()
    })

    fireEvent.click(screen.getByTestId('simulate-local-edit'))

    rerender(<FlowEditorInline flowId="flow-123" refreshToken={1} />)

    await waitFor(() => {
      expect(screen.getByText(/AI-მ განაახლა გრაფი/)).toBeInTheDocument()
    })
    expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByText('ჩატვირთე ხელახლა'))

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(2)
    })
  })
})
```

Add `fireEvent` to the testing-library import at the top of the file if not already imported.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx vitest run src/components/FlowEditorInline.test.tsx`
Expected: FAIL — "loads the latest draft" shows `1 nodes` (oldest version), refresh tests fail (no `refreshToken` prop)

- [ ] **Step 3: Implement**

In `frontend/src/components/FlowEditorInline.tsx`:

1. Props:

```tsx
interface FlowEditorInlineProps {
  flowId: string
  /** Bumped by the parent when the AI mutates the graph — triggers a re-fetch */
  refreshToken?: number
  /** Called when the user clicks the "open in editor" button */
  onOpenFullEditor?: (flowId: string) => void
}

export default function FlowEditorInline({ flowId, refreshToken, onOpenFullEditor }: FlowEditorInlineProps) {
```

2. Add a module-level helper above the component (backend returns versions ascending, so `versions[0]` is the oldest — pick the working version the AI edits):

```tsx
function pickWorkingVersion(versions: FlowVersion[]): FlowVersion | null {
  if (!versions || versions.length === 0) return null
  const drafts = versions.filter(v => v.status === 'draft')
  const pool = drafts.length > 0 ? drafts : versions
  return pool.reduce((a, b) => (b.version_number > a.version_number ? b : a))
}
```

3. Add state/refs next to the existing save state (line ~68):

```tsx
  const [staleNotice, setStaleNotice] = useState(false)
  const [canvasKey, setCanvasKey] = useState(0)
  const hasChangesRef = useRef(false)
  const prevRefreshRef = useRef(refreshToken)
```

4. Replace the load effect (lines 114–137) with a reusable `loadFlow` + two effects:

```tsx
  const loadFlow = useCallback(() => {
    if (!flowId) {
      setLoading(false)
      return
    }

    setLoading(true)
    setError(null)

    Promise.all([fetchFlow(flowId), fetchFlowVersions(flowId)])
      .then(([flowData, versions]) => {
        setFlow(flowData)
        setFlowVersion(pickWorkingVersion(versions))
        setHasChanges(false)
        hasChangesRef.current = false
        setStaleNotice(false)
        setCanvasKey(k => k + 1)
      })
      .catch(err => {
        setError(err.message)
      })
      .finally(() => {
        setLoading(false)
      })
  }, [flowId])

  useEffect(() => {
    loadFlow()
  }, [loadFlow])

  // AI edited the graph: refresh if safe, otherwise warn (never clobber local edits)
  useEffect(() => {
    if (refreshToken === undefined || refreshToken === prevRefreshRef.current) return
    prevRefreshRef.current = refreshToken
    if (hasChangesRef.current) {
      setStaleNotice(true)
    } else {
      loadFlow()
    }
  }, [refreshToken, loadFlow])
```

5. In `handleGraphChange` (line 150), add `hasChangesRef.current = true` next to `setHasChanges(true)`. In `saveGraph` (line 212), add `hasChangesRef.current = false` next to `setHasChanges(false)`.

6. In the canvas area JSX (`<div className="fei-canvas-area">`, ~line 493), add the banner just before `<FlowCanvas`, and add `key={canvasKey}` to `<FlowCanvas>` so a reload rebuilds the canvas from the fresh graph:

```tsx
        {staleNotice && (
          <div className="fei-stale-banner">
            <span>AI-მ განაახლა გრაფი — ხელახლა ჩატვირთვა წაშლის შენს შეუნახავ ცვლილებებს.</span>
            <button type="button" onClick={loadFlow}>ჩატვირთე ხელახლა</button>
            <button type="button" onClick={() => setStaleNotice(false)}>დარჩი ჩემს ვერსიაზე</button>
          </div>
        )}
        <FlowCanvas
          key={canvasKey}
          ref={canvasRef}
          ...
```

7. Append to `frontend/src/components/flow-editor-inline.css`:

```css
.fei-stale-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  font-size: 12px;
  background: var(--color-warn-bg, #fff3cd);
  border-bottom: 1px solid var(--color-warn-border, #ffe69c);
}

.fei-stale-banner button {
  padding: 2px 8px;
  font-size: 12px;
  cursor: pointer;
}
```

(Check the top of the CSS file for existing design-token variable names — if the project defines warning tokens, use those instead of the fallbacks.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx vitest run src/components/FlowEditorInline.test.tsx`
Expected: PASS (all tests, including pre-existing — if a pre-existing test depended on `versions[0]` being picked, update its mock to make the intended version the latest draft)

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/FlowEditorInline.tsx frontend/src/components/FlowEditorInline.test.tsx \
  frontend/src/components/flow-editor-inline.css
git commit -m "feat(fe/editor): refresh inline editor on AI graph edits

Adds a refreshToken prop: re-fetches the graph when the AI mutates it,
or shows a stale banner when the operator has unsaved local edits.
Also fixes version selection — the editor now opens the latest draft
instead of the oldest version (backend returns ascending order).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Wire `WorkPage` → `RightPanel` → `FlowEditorInline`, full verification

**Files:**
- Modify: `frontend/src/pages/WorkPage.tsx` (state near line 54; `<ChatPanel>` at ~line 307; `<RightPanel>` at ~line 328)
- Modify: `frontend/src/components/RightPanel.tsx` (props at line 8; `<FlowEditorInline>` at ~line 88)

**Interfaces:**
- Consumes: `ChatPanel.onFlowMutated` (Task 4), `FlowEditorInline.refreshToken` (Task 5)
- Produces: the complete AI-edit → editor-refresh loop; final green build

- [ ] **Step 1: Wire WorkPage**

In `frontend/src/pages/WorkPage.tsx`:

1. Add state next to `contextContent` (line 54):

```tsx
  const [editorRefreshToken, setEditorRefreshToken] = useState(0)
```

2. Add a handler next to `handleContextContent` (~line 201):

```tsx
  // AI mutated a flow graph → tell the inline editor to refresh
  const handleFlowMutated = useCallback(() => {
    setEditorRefreshToken(n => n + 1)
  }, [])
```

3. Pass to `<ChatPanel>` (~line 307): `onFlowMutated={handleFlowMutated}`

4. Pass to `<RightPanel>` (~line 328): `editorRefreshToken={editorRefreshToken}`

- [ ] **Step 2: Wire RightPanel**

In `frontend/src/components/RightPanel.tsx`:

1. Add to `RightPanelProps` (line 8–21):

```tsx
  /** Bumped when the AI mutates a flow graph — forwarded to the inline editor */
  editorRefreshToken?: number
```

2. Add `editorRefreshToken,` to the destructured props (~line 23–34).

3. Pass to `<FlowEditorInline>` (~line 88):

```tsx
          <FlowEditorInline
            flowId={editorContent.flowId}
            refreshToken={editorRefreshToken}
            onOpenFullEditor={onOpenFullEditor}
          />
```

- [ ] **Step 3: Run the full frontend suite and typecheck**

Run: `cd frontend && npx vitest run && npm run build`
Expected: all tests PASS; `tsc`/vite build succeeds with no type errors

- [ ] **Step 4: Run the full backend verification**

Run: `mix precommit`
Expected: compile with no warnings, no unused deps, format clean, all tests pass

If `mix format --check-formatted` fails, run `mix format` and re-run `mix precommit`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/pages/WorkPage.tsx frontend/src/components/RightPanel.tsx
git commit -m "feat(fe/work): wire AI graph-edit refresh through WorkPage to inline editor

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
