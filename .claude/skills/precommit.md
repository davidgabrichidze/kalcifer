# /precommit — Run full precommit checks

Run the project's precommit suite and analyze/fix any issues.

## Steps

### 1. Run precommit

```bash
mix precommit
```

This runs (in order):
1. `mix compile --warnings-as-errors` — no compiler warnings allowed
2. `mix deps.unlock --check-unused` — no unused dependencies
3. `mix format --check-formatted` — code is formatted
4. `mix test` — all tests pass

### 2. If compilation fails

- Common: `@doc` on private functions. Remove the `@doc` and use a plain comment instead
- Common: unused variables. Prefix with underscore `_var` or remove
- Common: missing alias. Add alias (alphabetically ordered!)

### 3. If format check fails

Run `mix format` to auto-fix, then review changes.

### 4. If Credo fails

Run `mix credo --strict` separately for detailed messages.

Common issues:
- **AliasOrder**: Aliases must be alphabetically ordered
- **LargeNumbers**: Numbers > 9999 need underscores (`86_400` not `86400`)
- **LineLength**: Max 120 characters
- **Readability.ModuleDoc**: Add `@moduledoc false` for internal modules

### 5. If tests fail

Run failing tests with `--trace` to see names:
```bash
mix test --trace path/to/failing_test.exs
```

Common test issues:
- ETS registry: Use `>= N` not `== N` for count assertions
- Async tests with shared state: Use `async: false`
- FlowServer timing: Add `Process.sleep(200)` or use monitors

### 6. Report results

Summarize: number of tests, pass/fail, any warnings fixed.
