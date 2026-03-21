# Contributing to Kalcifer

Thank you for your interest in contributing to Kalcifer! This guide will help you get started.

## Getting Started

### Prerequisites

- Elixir ~> 1.18 / OTP 28
- PostgreSQL 16+
- Git

### Setup

```bash
git clone https://github.com/kalcifer/kalcifer
cd kalcifer
make setup
make dev
```

The API will be available at `http://localhost:4500`.

### Verify your setup

```bash
curl http://localhost:4500/api/v1/health
# → {"status":"ok"}
```

## Development Workflow

### Running Tests

```bash
make test           # Run all tests with --trace
make lint           # Format check + Credo strict + compile warnings
make ci             # Full CI check (lint + test + dialyzer)
```

### Code Style

We enforce strict code quality:

- **Formatter**: `mix format` — run before every commit
- **Credo strict**: No warnings allowed
- **Dialyzer**: Type specs encouraged
- **Max line length**: 120 characters
- **Aliases**: Alphabetically ordered

### Commit Messages

We use conventional commits:

```
feat: implement event routing for waiting flow instances
fix: correct duration parsing for fractional hours
test: add edge case tests for flow server resume
refactor: extract frequency cap helpers into separate module
docs: add CLAUDE.md with project conventions
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

## What to Contribute

### Good First Issues

Look for issues tagged `good-first-issue` on GitHub.

### Custom Nodes

Kalcifer's plugin architecture makes it easy to add new nodes:

1. Create a module implementing `Kalcifer.Engine.Nodes.Behaviour`
2. Register it in `NodeRegistry`
3. Add tests
4. Submit a PR

See `docs/node-development.md` for the full guide.

### Channel Providers

We welcome new channel provider implementations:

- Push notification providers (FCM, APNs)
- WhatsApp Business API
- Slack / Discord
- Custom webhook templates

### Documentation

Documentation improvements are always welcome — typo fixes, better examples, translations.

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes with tests
4. Run `make ci` to verify everything passes
5. Submit a PR with a clear description

### PR Checklist

- [ ] Tests pass (`make test`)
- [ ] Code formatted (`mix format`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation updated if needed
- [ ] Conventional commit messages

## Architecture Overview

See `docs/02-ARCHITECTURE.md` for the full architecture document. Key concepts:

- **Process-per-instance**: Each FlowInstance gets a GenServer
- **Plugin nodes**: NodeRegistry (ETS) maps type strings to modules
- **Generic context**: Execution passes a context map through nodes

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

- Open a GitHub Discussion for general questions
- Open an Issue for bugs or feature requests
- Join our Discord for real-time chat

Thank you for helping make Kalcifer better!
