# /new-hook — Create a custom React hook

The user provides: hook name, purpose, dependencies.

## Steps

### 1. Create hook

File: `frontend/src/hooks/use-{kebab-case-name}.ts`

```ts
import { useState, useEffect, useCallback } from "react";

interface Use{PascalCaseName}Options {
  // Hook options
}

interface Use{PascalCaseName}Return {
  // Return type
}

export function use{PascalCaseName}(options: Use{PascalCaseName}Options): Use{PascalCaseName}Return {
  // Implementation

  return {
    // Return values
  };
}
```

### 2. Conventions

**Naming**: Always prefix with `use`, file name is `use-{kebab-case}.ts`

**Common patterns in Kalcifer**:

```ts
// WebSocket subscription hook
export function useFlowUpdates(flowId: string) {
  const [updates, setUpdates] = useState<FlowUpdate[]>([]);

  useEffect(() => {
    const channel = socket.channel(`flow:${flowId}`);
    channel.on("update", (payload) => setUpdates((prev) => [...prev, payload]));
    channel.join();
    return () => { channel.leave(); };
  }, [flowId]);

  return updates;
}

// Debounced value hook
export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

// Local storage hook
export function useLocalStorage<T>(key: string, initialValue: T) {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = useCallback((value: T | ((val: T) => T)) => {
    const valueToStore = value instanceof Function ? value(storedValue) : value;
    setStoredValue(valueToStore);
    window.localStorage.setItem(key, JSON.stringify(valueToStore));
  }, [key, storedValue]);

  return [storedValue, setValue] as const;
}
```

**Rules**:
- Hooks must be pure functions (no side effects outside useEffect)
- Always clean up subscriptions/timers in useEffect return
- Use `useCallback` for returned functions to prevent unnecessary re-renders
- Type everything explicitly — no `any`
- Export the hook AND its types

### 3. Create test

File: `frontend/src/hooks/use-{kebab-case-name}.test.ts`

```ts
import { renderHook, act } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { use{PascalCaseName} } from "./use-{kebab-case-name}";

describe("use{PascalCaseName}", () => {
  it("returns initial state", () => {
    const { result } = renderHook(() =>
      use{PascalCaseName}({ /* options */ })
    );
    expect(result.current.someValue).toBe(expectedValue);
  });

  it("updates state on action", () => {
    const { result } = renderHook(() =>
      use{PascalCaseName}({ /* options */ })
    );

    act(() => {
      result.current.someAction();
    });

    expect(result.current.someValue).toBe(newExpectedValue);
  });

  it("cleans up on unmount", () => {
    const { unmount } = renderHook(() =>
      use{PascalCaseName}({ /* options */ })
    );
    unmount();
    // Verify cleanup happened
  });
});
```

### 4. Verify

```bash
cd frontend && npx vitest run src/hooks/use-{kebab-case-name}.test.ts
npx tsc --noEmit
```
