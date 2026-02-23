# /new-flow-node-ui — Create a ReactFlow custom node UI

Create the visual representation and configuration panel for a flow engine node.
The user provides: node type (matching the backend registry key), category.

## Context

The flow designer uses ReactFlow (xyflow) for the visual canvas. Each engine node type needs:
1. **Canvas node** — visual representation on the flow canvas
2. **Config panel** — sidebar form for editing node configuration
3. **Zustand slice** — state management for node data

## Steps

### 1. Create canvas node component

File: `frontend/src/features/flow-designer/nodes/{node-type}/{PascalCaseName}Node.tsx`

```tsx
import { memo } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import { cn } from "@/lib/utils";

// Category → color mapping
const CATEGORY_STYLES = {
  trigger: "border-green-500 bg-green-50",
  condition: "border-amber-500 bg-amber-50",
  wait: "border-blue-500 bg-blue-50",
  action: "border-purple-500 bg-purple-50",
  end: "border-red-500 bg-red-50",
} as const;

export interface {PascalCaseName}NodeData {
  label: string;
  config: {
    // Match the backend config_schema fields
  };
}

export const {PascalCaseName}Node = memo(({ data, selected }: NodeProps<{PascalCaseName}NodeData>) => {
  return (
    <div
      className={cn(
        "min-w-[180px] rounded-lg border-2 px-4 py-3 shadow-sm",
        CATEGORY_STYLES.{category},
        selected && "ring-2 ring-blue-500 ring-offset-2"
      )}
    >
      {/* Input handle (except for trigger nodes) */}
      <Handle type="target" position={Position.Top} className="!bg-gray-400" />

      <div className="flex items-center gap-2">
        <span className="text-lg">{/* Icon */}</span>
        <div>
          <p className="text-sm font-medium text-gray-900">{data.label}</p>
          <p className="text-xs text-gray-500">{/* summary from config */}</p>
        </div>
      </div>

      {/* Output handle (except for end nodes) */}
      <Handle type="source" position={Position.Bottom} className="!bg-gray-400" />

      {/* For branching nodes (condition, wait_for_event), add multiple source handles: */}
      {/* <Handle type="source" position={Position.Bottom} id="true_branch" style={{ left: "30%" }} /> */}
      {/* <Handle type="source" position={Position.Bottom} id="false_branch" style={{ left: "70%" }} /> */}
    </div>
  );
});
{PascalCaseName}Node.displayName = "{PascalCaseName}Node";
```

**Handle rules by category**:
- `trigger`: No target handle (entry point), one source handle
- `condition`: One target, multiple source handles (one per branch)
- `wait`: One target, multiple source handles (event_received, timed_out)
- `action`: One target, one source
- `end`: One target, no source handle

### 2. Create config panel

File: `frontend/src/features/flow-designer/nodes/{node-type}/{PascalCaseName}ConfigPanel.tsx`

```tsx
import { type {PascalCaseName}NodeData } from "./{PascalCaseName}Node";

interface {PascalCaseName}ConfigPanelProps {
  nodeId: string;
  data: {PascalCaseName}NodeData;
  onChange: (data: Partial<{PascalCaseName}NodeData["config"]>) => void;
}

export function {PascalCaseName}ConfigPanel({ nodeId, data, onChange }: {PascalCaseName}ConfigPanelProps) {
  return (
    <div className="flex flex-col gap-4 p-4">
      <h3 className="text-sm font-semibold text-gray-900">{Node Type} Configuration</h3>

      {/* Form fields matching config_schema from backend */}
      <label className="flex flex-col gap-1">
        <span className="text-xs font-medium text-gray-700">Field Name</span>
        <input
          type="text"
          value={data.config.field_name ?? ""}
          onChange={(e) => onChange({ field_name: e.target.value })}
          className="rounded-md border border-gray-300 px-3 py-2 text-sm"
        />
      </label>
    </div>
  );
}
```

### 3. Register node type

Edit `frontend/src/features/flow-designer/node-registry.ts`:

```ts
import { {PascalCaseName}Node } from "./nodes/{node-type}/{PascalCaseName}Node";
import { {PascalCaseName}ConfigPanel } from "./nodes/{node-type}/{PascalCaseName}ConfigPanel";

export const nodeTypes = {
  // ... existing entries
  {node_type}: {PascalCaseName}Node,
} as const;

export const configPanels = {
  // ... existing entries
  {node_type}: {PascalCaseName}ConfigPanel,
} as const;

export const nodeDefaults: Record<string, { label: string; category: string; config: object }> = {
  // ... existing entries
  {node_type}: {
    label: "{Human Readable Name}",
    category: "{category}",
    config: {
      // Default config values matching backend config_schema
    },
  },
};
```

### 4. Add Zustand slice (if complex state needed)

File: `frontend/src/features/flow-designer/store/{node-type}-slice.ts`

```ts
import { type StateCreator } from "zustand";

export interface {PascalCaseName}Slice {
  // Node-specific state
  update{PascalCaseName}Config: (nodeId: string, config: Partial<Config>) => void;
}

export const create{PascalCaseName}Slice: StateCreator<{PascalCaseName}Slice> = (set) => ({
  update{PascalCaseName}Config: (nodeId, config) =>
    set((state) => {
      // Update node data in the flow graph state
    }),
});
```

### 5. Create barrel export

File: `frontend/src/features/flow-designer/nodes/{node-type}/index.ts`

```ts
export { {PascalCaseName}Node, type {PascalCaseName}NodeData } from "./{PascalCaseName}Node";
export { {PascalCaseName}ConfigPanel } from "./{PascalCaseName}ConfigPanel";
```

### 6. Create test

File: `frontend/src/features/flow-designer/nodes/{node-type}/{PascalCaseName}Node.test.tsx`

```tsx
import { render, screen } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import { describe, it, expect } from "vitest";
import { {PascalCaseName}Node } from "./{PascalCaseName}Node";

describe("{PascalCaseName}Node", () => {
  const defaultProps = {
    id: "test-node",
    data: { label: "Test", config: {} },
    selected: false,
    type: "{node_type}",
    // ... other required NodeProps
  } as any;

  it("renders label", () => {
    render(
      <ReactFlowProvider>
        <{PascalCaseName}Node {...defaultProps} />
      </ReactFlowProvider>
    );
    expect(screen.getByText("Test")).toBeInTheDocument();
  });

  it("shows selected state", () => {
    render(
      <ReactFlowProvider>
        <{PascalCaseName}Node {...defaultProps} selected={true} />
      </ReactFlowProvider>
    );
    // Verify ring/highlight class applied
  });
});
```

### 7. Verify

```bash
cd frontend && npx vitest run src/features/flow-designer/nodes/{node-type}/
npx tsc --noEmit
```

## Important

The node type string MUST match the backend NodeRegistry key exactly.
E.g. backend `"send_email"` → frontend `nodeTypes.send_email`.
