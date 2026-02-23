# /frontend-check — Run frontend quality checks

Run all frontend quality checks and fix issues.

## Steps

### 1. TypeScript type check

```bash
cd frontend && npx tsc --noEmit
```

Common fixes:
- Missing types: Add explicit type annotations
- `any` usage: Replace with proper types
- Null safety: Use optional chaining `?.` and nullish coalescing `??`
- Import errors: Check path aliases (`@/` mapping)

### 2. Lint

```bash
cd frontend && npx eslint src/ --ext .ts,.tsx
```

Common fixes:
- Unused imports: Remove them
- React hooks dependencies: Add missing deps to useEffect/useCallback/useMemo arrays
- Exhaustive deps: Follow the eslint-plugin-react-hooks suggestions
- Import order: Follow the configured import sorting

### 3. Format

```bash
cd frontend && npx prettier --check "src/**/*.{ts,tsx}"
```

Auto-fix: `npx prettier --write "src/**/*.{ts,tsx}"`

### 4. Tests

```bash
cd frontend && npx vitest run
```

If specific tests fail:
```bash
npx vitest run src/path/to/failing.test.tsx
```

### 5. Build

```bash
cd frontend && npm run build
```

Build failures usually indicate:
- Dead code that type-check missed (tree shaking reveals issues)
- Missing environment variables
- Import cycle issues

### 6. Report

Summarize:
- Type errors found/fixed
- Lint issues found/fixed
- Test results (pass/fail count)
- Build status
