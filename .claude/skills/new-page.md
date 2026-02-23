# /new-page — Create a new page with routing

Create a new page component with route registration.
The user provides: page name, route path, layout context.

## Steps

### 1. Create page component

File: `frontend/src/pages/{kebab-case-name}/{PascalCaseName}Page.tsx`

```tsx
import { useParams } from "react-router-dom";

export function {PascalCaseName}Page() {
  // const { id } = useParams();  // if route has params

  return (
    <div className="flex flex-col gap-6 p-6">
      <header>
        <h1 className="text-2xl font-semibold text-gray-900">
          {Page Title}
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          {Page description}
        </p>
      </header>

      <main>
        {/* Page content */}
      </main>
    </div>
  );
}
```

### 2. Create barrel export

File: `frontend/src/pages/{kebab-case-name}/index.ts`

```ts
export { {PascalCaseName}Page } from "./{PascalCaseName}Page";
```

### 3. Add route

Edit `frontend/src/router.tsx` (or wherever routes are defined):

```tsx
import { {PascalCaseName}Page } from "@/pages/{kebab-case-name}";

// In route configuration:
{
  path: "/{route-path}",
  element: <{PascalCaseName}Page />,
}

// Or with layout:
{
  path: "/{route-path}",
  element: <AppLayout />,
  children: [
    { index: true, element: <{PascalCaseName}Page /> },
  ],
}
```

### 4. Create page test

File: `frontend/src/pages/{kebab-case-name}/{PascalCaseName}Page.test.tsx`

```tsx
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import { describe, it, expect } from "vitest";
import { {PascalCaseName}Page } from "./{PascalCaseName}Page";

function renderWithProviders(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/{route-path}"]}>
        {ui}
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe("{PascalCaseName}Page", () => {
  it("renders page title", () => {
    renderWithProviders(<{PascalCaseName}Page />);
    expect(screen.getByText("{Page Title}")).toBeInTheDocument();
  });
});
```

### 5. Conventions

- Pages go in `src/pages/`, components in `src/components/`
- Pages are responsible for data fetching (via TanStack Query hooks)
- Pages compose components, don't contain complex UI logic
- Wrap with appropriate layout component
- Handle loading and error states

### 6. Verify

```bash
cd frontend && npx vitest run src/pages/{kebab-case-name}/
npx tsc --noEmit
```
