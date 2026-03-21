.PHONY: setup dev test lint release docker-build docker-up docker-down ci clean

# =====================================================
# Kalcifer — Development Commands
# =====================================================

# Quick start: make setup && make dev
setup:
	mix deps.get
	mix ecto.create
	mix ecto.migrate
	@echo "\n✓ Setup complete. Run 'make dev' to start the server."

dev:
	mix phx.server

# Run with iex console
console:
	iex -S mix phx.server

# =====================================================
# Testing & Quality
# =====================================================

test:
	mix test --trace

test-watch:
	mix test --trace --stale

lint:
	mix compile --warnings-as-errors
	mix format --check-formatted
	mix credo --strict

dialyzer:
	mix dialyzer

# Full precommit check (same as CI)
ci: lint test dialyzer
	@echo "\n✓ All checks passed."

# Alias for ci
precommit: ci

# =====================================================
# Docker
# =====================================================

docker-build:
	docker build -t kalcifer:latest -f docker/Dockerfile .

docker-up:
	docker compose -f docker/docker-compose.yml up -d

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-prod:
	docker compose -f docker-compose.prod.yml up -d

# =====================================================
# Release
# =====================================================

release:
	MIX_ENV=prod mix release

# =====================================================
# Database
# =====================================================

db-create:
	mix ecto.create

db-migrate:
	mix ecto.migrate

db-rollback:
	mix ecto.rollback

db-reset:
	mix ecto.reset

db-seed:
	mix run priv/repo/seeds.exs

# =====================================================
# Fly.io Deployment
# =====================================================

deploy:
	fly deploy

deploy-console:
	fly ssh console --pty -C "/app/bin/kalcifer remote"

deploy-migrate:
	fly ssh console -C "/app/bin/migrate"

deploy-logs:
	fly logs

deploy-status:
	fly status

# =====================================================
# Cleanup
# =====================================================

clean:
	rm -rf _build deps
	mix deps.get
