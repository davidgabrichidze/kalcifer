# /new-component — Create a React component

Create a new React component with TypeScript, Radix UI primitives, and Tailwind CSS.
The user provides: component name, purpose, props.

## Tech stack

- React 18+ with TypeScript
- Radix UI primitives (accessible, unstyled)
- Tailwind CSS for styling
- Vitest for testing

## Steps

### 1. Create component file

File: `frontend/src/components/{kebab-case-name}/{PascalCaseName}.tsx`

```tsx
import { type ComponentPropsWithoutRef, forwardRef } from "react";
import { cn } from "@/lib/utils";

export interface {PascalCaseName}Props extends ComponentPropsWithoutRef<"div"> {
  // Add specific props here
}

export const {PascalCaseName} = forwardRef<HTMLDivElement, {PascalCaseName}Props>(
  ({ className, ...props }, ref) => {
    return (
      <div
        ref={ref}
        className={cn(
          // Base styles
          "relative",
          className
        )}
        {...props}
      />
    );
  }
);
{PascalCaseName}.displayName = "{PascalCaseName}";
```

**For Radix UI based components** (dialog, dropdown, popover, etc.):

```tsx
import * as RadixDialog from "@radix-ui/react-dialog";
import { cn } from "@/lib/utils";

export interface {PascalCaseName}Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  children: React.ReactNode;
}

export function {PascalCaseName}({ open, onOpenChange, children }: {PascalCaseName}Props) {
  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 bg-black/50" />
        <RadixDialog.Content className="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-lg bg-white p-6 shadow-lg">
          {children}
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}
```

### 2. Create barrel export

File: `frontend/src/components/{kebab-case-name}/index.ts`

```ts
export { {PascalCaseName} } from "./{PascalCaseName}";
export type { {PascalCaseName}Props } from "./{PascalCaseName}";
```

### 3. Create test

File: `frontend/src/components/{kebab-case-name}/{PascalCaseName}.test.tsx`

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi } from "vitest";
import { {PascalCaseName} } from "./{PascalCaseName}";

describe("{PascalCaseName}", () => {
  it("renders without crashing", () => {
    render(<{PascalCaseName} />);
  });

  it("applies custom className", () => {
    render(<{PascalCaseName} className="custom" data-testid="comp" />);
    expect(screen.getByTestId("comp")).toHaveClass("custom");
  });

  it("forwards ref", () => {
    const ref = { current: null };
    render(<{PascalCaseName} ref={ref} />);
    expect(ref.current).toBeInstanceOf(HTMLElement);
  });
});
```

### 4. Conventions

- **File structure**: Each component in its own directory with index.ts barrel
- **Styling**: Tailwind utility classes, `cn()` for conditional classes
- **Accessibility**: Use Radix UI primitives for interactive components (dialogs, dropdowns, tooltips)
- **Props**: Extend native HTML element props with `ComponentPropsWithoutRef`
- **Refs**: Use `forwardRef` for leaf components
- **No inline styles**: Use Tailwind classes only
- **Naming**: PascalCase for components, kebab-case for directories

### 5. Verify

```bash
cd frontend && npx vitest run src/components/{kebab-case-name}/
npx tsc --noEmit
```
