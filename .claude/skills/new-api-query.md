# /new-api-query — Create a TanStack Query hook for a backend endpoint

The user provides: endpoint path, HTTP method, request/response types.

## Steps

### 1. Define types

File: `frontend/src/api/types/{resource}.ts`

```ts
export interface {Resource} {
  id: string;
  name: string;
  status: string;
  // ... fields matching backend serialize/1
  inserted_at: string;
  updated_at: string;
}

export interface Create{Resource}Request {
  name: string;
  // ... creation fields
}

export interface Update{Resource}Request {
  name?: string;
  // ... update fields (all optional)
}

export interface {Resource}ListResponse {
  data: {Resource}[];
}

export interface {Resource}Response {
  data: {Resource};
}
```

### 2. Create API client function

File: `frontend/src/api/{resource}.ts`

```ts
import { apiClient } from "./client";
import type {
  {Resource},
  Create{Resource}Request,
  Update{Resource}Request,
  {Resource}ListResponse,
  {Resource}Response,
} from "./types/{resource}";

const BASE_PATH = "/api/v1/{resources}";

export const {resource}Api = {
  list: async (params?: { status?: string }): Promise<{Resource}[]> => {
    const res = await apiClient.get<{Resource}ListResponse>(BASE_PATH, { params });
    return res.data.data;
  },

  get: async (id: string): Promise<{Resource}> => {
    const res = await apiClient.get<{Resource}Response>(`${BASE_PATH}/${id}`);
    return res.data.data;
  },

  create: async (data: Create{Resource}Request): Promise<{Resource}> => {
    const res = await apiClient.post<{Resource}Response>(BASE_PATH, data);
    return res.data.data;
  },

  update: async (id: string, data: Update{Resource}Request): Promise<{Resource}> => {
    const res = await apiClient.put<{Resource}Response>(`${BASE_PATH}/${id}`, data);
    return res.data.data;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`${BASE_PATH}/${id}`);
  },

  // Custom actions:
  activate: async (id: string): Promise<{Resource}> => {
    const res = await apiClient.post<{Resource}Response>(`${BASE_PATH}/${id}/activate`);
    return res.data.data;
  },
};
```

### 3. Create TanStack Query hooks

File: `frontend/src/hooks/api/use-{resource}.ts`

```ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { {resource}Api } from "@/api/{resource}";
import type { Create{Resource}Request, Update{Resource}Request } from "@/api/types/{resource}";

// Query keys — centralized for cache invalidation
export const {resource}Keys = {
  all: ["{resources}"] as const,
  lists: () => [...{resource}Keys.all, "list"] as const,
  list: (params?: { status?: string }) => [...{resource}Keys.lists(), params] as const,
  details: () => [...{resource}Keys.all, "detail"] as const,
  detail: (id: string) => [...{resource}Keys.details(), id] as const,
};

// --- Queries ---

export function use{Resources}(params?: { status?: string }) {
  return useQuery({
    queryKey: {resource}Keys.list(params),
    queryFn: () => {resource}Api.list(params),
  });
}

export function use{Resource}(id: string) {
  return useQuery({
    queryKey: {resource}Keys.detail(id),
    queryFn: () => {resource}Api.get(id),
    enabled: !!id,
  });
}

// --- Mutations ---

export function useCreate{Resource}() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: Create{Resource}Request) => {resource}Api.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: {resource}Keys.lists() });
    },
  });
}

export function useUpdate{Resource}() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Update{Resource}Request }) =>
      {resource}Api.update(id, data),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: {resource}Keys.detail(id) });
      queryClient.invalidateQueries({ queryKey: {resource}Keys.lists() });
    },
  });
}

export function useDelete{Resource}() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => {resource}Api.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: {resource}Keys.lists() });
    },
  });
}

export function useActivate{Resource}() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => {resource}Api.activate(id),
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: {resource}Keys.detail(id) });
      queryClient.invalidateQueries({ queryKey: {resource}Keys.lists() });
    },
  });
}
```

### 4. Usage example

```tsx
function {Resource}ListPage() {
  const { data: {resources}, isLoading, error } = use{Resources}();
  const create{Resource} = useCreate{Resource}();

  if (isLoading) return <Spinner />;
  if (error) return <ErrorMessage error={error} />;

  return (
    <div>
      {resources?.map(item => <{Resource}Card key={item.id} {resource}={item} />)}
      <button onClick={() => create{Resource}.mutate({ name: "New" })}>
        Create
      </button>
    </div>
  );
}
```

### 5. Conventions

- **Query keys**: Always use the factory pattern (`{resource}Keys.detail(id)`)
- **Cache invalidation**: Mutations invalidate related queries via `queryClient.invalidateQueries`
- **Error handling**: Let errors propagate to error boundaries, don't swallow them
- **Optimistic updates**: Use for UX-critical operations (status changes, reordering)
- **Enabled**: Use `enabled: !!id` to prevent queries with undefined params
- **Stale time**: Set appropriate `staleTime` for data that doesn't change frequently

### 6. Verify

```bash
cd frontend && npx vitest run src/hooks/api/use-{resource}.test.ts
npx tsc --noEmit
```
