# Kalcifer — Deployment Strategy

**Version**: 1.0
**Date**: 2026-02-22
**Status**: Draft

---

## 1. Deployment Tiers

Kalcifer supports three deployment models, from simplest to most scalable:

```
Tier 1: Single Machine        Tier 2: Docker Compose       Tier 3: Kubernetes
(Development/Small)            (Production/Medium)          (Enterprise/Large)

┌──────────────┐              ┌──────────────────┐         ┌──────────────────────┐
│  Kalcifer   │              │  docker-compose   │         │    Kubernetes        │
│  + PG        │              │  ┌─────────────┐  │         │  ┌────┐ ┌────┐ ┌────┐│
│  + ES        │              │  │ Kalcifer   │  │         │  │ OF │ │ OF │ │ OF ││
│  (embedded)  │              │  │ PG          │  │         │  └────┘ └────┘ └────┘│
│              │              │  │ ES          │  │         │  ┌────┐  ┌────┐      │
└──────────────┘              │  │ CH          │  │         │  │ PG │  │ ES │      │
                              │  └─────────────┘  │         │  └────┘  └────┘      │
                              └──────────────────┘         │  ┌────┐              │
                                                           │  │ CH │              │
                                                           │  └────┘              │
                                                           └──────────────────────┘

Target: 1K journeys           Target: 100K journeys        Target: 1M+ journeys
Setup: 2 minutes              Setup: 5 minutes             Setup: 30 minutes
```

---

## 2. Tier 1 — Single Binary

For development, evaluation, and small deployments.

### Elixir Release

```dockerfile
# docker/Dockerfile
# Stage 1: Build
FROM elixir:1.17-otp-27-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
COPY rel rel

RUN mix compile
RUN mix release

# Stage 2: Runtime
FROM alpine:3.20 AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/kalcifer ./

ENV PHX_HOST=localhost
ENV PHX_PORT=4500

EXPOSE 4500

CMD ["bin/kalcifer", "start"]
```

**Image size target**: < 100MB (Alpine-based, no dev dependencies)

### Standalone with Embedded SQLite (Tier 1 only)

For the simplest possible deployment (evaluation only):

```bash
# Download and run — nothing else needed
curl -L https://github.com/kalcifer/kalcifer/releases/latest/download/kalcifer-linux-amd64 -o kalcifer
chmod +x kalcifer
./kalcifer start

# Kalcifer starts on localhost:4500
# Uses embedded SQLite for state (no PostgreSQL needed)
# Elasticsearch and ClickHouse features disabled
# Perfect for: evaluation, demos, single-user testing
```

---

## 3. Tier 2 — Docker Compose (Primary Target)

This is the recommended production deployment for most users.

```yaml
# docker/docker-compose.yml
version: "3.8"

services:
  kalcifer:
    image: ghcr.io/kalcifer/kalcifer:latest
    ports:
      - "4500:4500"
    environment:
      DATABASE_URL: ecto://kalcifer:kalcifer@postgres:5432/kalcifer
      ELASTICSEARCH_URL: http://elasticsearch:9200
      CLICKHOUSE_URL: http://clickhouse:8123
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      ENCRYPTION_KEY: ${ENCRYPTION_KEY}
      PHX_HOST: ${PHX_HOST:-localhost}
    depends_on:
      postgres:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
      clickhouse:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "bin/kalcifer", "rpc", "Kalcifer.Health.check()"]
      interval: 10s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "2"

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: kalcifer
      POSTGRES_PASSWORD: kalcifer
      POSTGRES_DB: kalcifer
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kalcifer"]
      interval: 5s
      timeout: 3s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 1G

  elasticsearch:
    image: elasticsearch:8.15.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 1G

  clickhouse:
    image: clickhouse/clickhouse-server:24-alpine
    volumes:
      - ch_data:/var/lib/clickhouse
    healthcheck:
      test: ["CMD-SHELL", "clickhouse-client --query 'SELECT 1'"]
      interval: 5s
      timeout: 3s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 1G

volumes:
  pg_data:
  es_data:
  ch_data:
```

### Setup Script

```bash
#!/bin/bash
# setup.sh — Get Kalcifer running in 5 minutes

set -e

echo "=== Kalcifer Setup ==="

# Generate secrets if not set
if [ -z "$SECRET_KEY_BASE" ]; then
  export SECRET_KEY_BASE=$(openssl rand -hex 64)
  echo "SECRET_KEY_BASE=$SECRET_KEY_BASE" >> .env
fi

if [ -z "$ENCRYPTION_KEY" ]; then
  export ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> .env
fi

# Start services
docker compose up -d

# Wait for health
echo "Waiting for services to be healthy..."
until docker compose exec kalcifer bin/kalcifer rpc "Kalcifer.Health.check()" 2>/dev/null; do
  sleep 2
done

# Run migrations
docker compose exec kalcifer bin/kalcifer eval "Kalcifer.Release.migrate()"

# Setup ClickHouse schema
docker compose exec kalcifer bin/kalcifer eval "Kalcifer.Release.setup_clickhouse()"

# Create default tenant
docker compose exec kalcifer bin/kalcifer eval \
  "Kalcifer.Release.create_tenant(\"default\", \"Default Workspace\")"

echo ""
echo "=== Kalcifer is ready! ==="
echo "Dashboard: http://localhost:4500"
echo "API: http://localhost:4500/api/v1"
echo "API Key: (check output above)"
```

### Minimum Hardware Requirements (Docker Compose)

| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| Kalcifer | 2 cores | 2 GB | 1 GB |
| PostgreSQL | 1 core | 1 GB | 10 GB |
| Elasticsearch | 1 core | 1 GB | 10 GB |
| ClickHouse | 1 core | 1 GB | 10 GB |
| **Total** | **4 cores** | **5 GB** | **31 GB** |

Recommended: 8 cores, 16 GB RAM for production loads up to 100K concurrent journeys.

---

## 4. Tier 3 — Kubernetes

For enterprise deployments requiring high availability, auto-scaling, and multi-region.

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kalcifer
spec:
  replicas: 3
  selector:
    matchLabels:
      app: kalcifer
  template:
    metadata:
      labels:
        app: kalcifer
    spec:
      containers:
        - name: kalcifer
          image: ghcr.io/kalcifer/kalcifer:latest
          ports:
            - containerPort: 4500
              name: http
            - containerPort: 4369
              name: epmd
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: kalcifer-secrets
                  key: database-url
            - name: CLUSTER_ENABLED
              value: "true"
            - name: CLUSTER_STRATEGY
              value: "kubernetes"
            - name: CLUSTER_KUBERNETES_SELECTOR
              value: "app=kalcifer"
            - name: CLUSTER_KUBERNETES_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: RELEASE_NODE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "4"
              memory: "4Gi"
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 4500
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 4500
            initialDelaySeconds: 30
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: kalcifer
spec:
  selector:
    app: kalcifer
  ports:
    - port: 4500
      targetPort: 4500
      name: http
  type: ClusterIP
---
# Headless service for Erlang clustering
apiVersion: v1
kind: Service
metadata:
  name: kalcifer-headless
spec:
  selector:
    app: kalcifer
  clusterIP: None
  ports:
    - port: 4369
      name: epmd
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: kalcifer
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kalcifer
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Pods
      pods:
        metric:
          name: kalcifer_active_journey_instances
        target:
          type: AverageValue
          averageValue: "50000"    # Scale when avg instances per pod > 50K
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
```

### Erlang Clustering in Kubernetes

```elixir
# config/runtime.exs
if System.get_env("CLUSTER_ENABLED") == "true" do
  config :libcluster,
    topologies: [
      k8s: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: System.get_env("CLUSTER_KUBERNETES_SERVICE", "kalcifer-headless"),
          application_name: "kalcifer",
          namespace: System.get_env("CLUSTER_KUBERNETES_NAMESPACE", "default"),
          polling_interval: 5_000
        ]
      ]
    ]
end
```

---

## 5. Zero-Downtime Deployment

### Rolling Update Strategy

```
Time ──────────────────────────────────────────►

Pod 1 (v1): ████████████████░░░░░░░░░░░░░░
                            │ drain │ stop
Pod 1 (v2):                       ████████████████
                                  │ start │ ready

Pod 2 (v1): ████████████████████████████░░░░░░
                                        │ drain
Pod 2 (v2):                                   ████████
                                              │ ready

Pod 3 (v1): ████████████████████████████████████░░
Pod 3 (v2):                                        ███

Journey instances migrate via Horde (distributed supervisor):
- Pod going down → instances gracefully handed off to remaining pods
- New pod joins → rebalances instances from other pods
```

### Graceful Shutdown

```elixir
# In application.ex
def stop(_state) do
  # 1. Stop accepting new HTTP connections
  KalciferWeb.Endpoint.config_change(%{draining: true}, [])

  # 2. Stop starting new journey instances
  Kalcifer.Engine.JourneySupervisor.drain()

  # 3. Wait for active nodes to complete (up to 30s)
  Kalcifer.Engine.await_active_nodes(timeout: 30_000)

  # 4. Persist all in-flight state
  Kalcifer.Engine.persist_all_states()

  # 5. Deregister from cluster
  # (libcluster handles this automatically)

  :ok
end
```

Kubernetes config:
```yaml
spec:
  terminationGracePeriodSeconds: 60    # Give 60s for graceful shutdown
  containers:
    - lifecycle:
        preStop:
          httpGet:
            path: /health/drain
            port: 4500
```

---

## 6. Backup & Recovery

### PostgreSQL

```bash
# Automated daily backup (docker-compose example)
# Add to crontab: 0 3 * * * /opt/kalcifer/backup.sh

#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
docker compose exec -T postgres pg_dump -U kalcifer kalcifer | gzip > backups/pg_$DATE.sql.gz

# Keep 30 days
find backups/ -name "pg_*.sql.gz" -mtime +30 -delete
```

### Point-in-Time Recovery

```bash
# PostgreSQL WAL archiving for PITR
# In docker-compose.yml, add to postgres:
environment:
  POSTGRES_INITDB_ARGS: "--wal-segsize=16"
command: >
  postgres
  -c wal_level=replica
  -c archive_mode=on
  -c archive_command='gzip < %p > /backups/wal/%f.gz'
```

### ClickHouse

```bash
# ClickHouse backup (less critical — can be rebuilt from PG events)
docker compose exec clickhouse clickhouse-backup create daily_$DATE
docker compose exec clickhouse clickhouse-backup upload daily_$DATE
```

### Elasticsearch

```bash
# ES snapshot (only customer profiles — can be rebuilt from source)
curl -X PUT "localhost:9200/_snapshot/backup/daily_$DATE?wait_for_completion=true"
```

### Disaster Recovery Plan

| Scenario | RTO | RPO | Procedure |
|----------|-----|-----|-----------|
| Kalcifer pod crash | 10s | 0 | OTP supervisor auto-restarts |
| Database corruption | 15 min | 5 min (WAL) | Restore from backup + WAL replay |
| Full cluster loss | 30 min | Daily backup | Restore PG, rebuild ES/CH indices |
| Region outage | 1 hour | Daily backup | Deploy to another region |

---

## 7. Monitoring & Alerting

### Health Check Endpoints

```
GET /health          → 200 if process is alive
GET /health/ready    → 200 if PG + ES + CH connected
GET /health/startup  → 200 if recovery complete

Response:
{
  "status": "ok",
  "checks": {
    "postgres": { "status": "ok", "latency_ms": 2 },
    "elasticsearch": { "status": "ok", "latency_ms": 15 },
    "clickhouse": { "status": "ok", "latency_ms": 8 },
    "engine": {
      "status": "ok",
      "active_instances": 45230,
      "memory_mb": 847
    }
  },
  "version": "0.3.0",
  "uptime_seconds": 432000
}
```

### Prometheus Metrics

```
# Engine metrics
kalcifer_active_journey_instances            gauge
kalcifer_journey_starts_total                counter
kalcifer_journey_completions_total            counter
kalcifer_journey_failures_total               counter
kalcifer_node_executions_total{node_type}     counter
kalcifer_node_execution_duration_ms{node_type} histogram
kalcifer_event_dispatch_total                 counter
kalcifer_event_dispatch_duration_ms           histogram
kalcifer_crash_recoveries_total               counter

# Channel metrics
kalcifer_channel_sends_total{channel,provider}    counter
kalcifer_channel_deliveries_total{channel}         counter
kalcifer_channel_bounces_total{channel}            counter
kalcifer_channel_send_duration_ms{channel}         histogram

# System metrics (via PromEx)
kalcifer_beam_process_count                   gauge
kalcifer_beam_memory_bytes{type}              gauge
kalcifer_ecto_query_duration_ms               histogram
kalcifer_oban_job_duration_ms{queue}          histogram
kalcifer_phoenix_request_duration_ms{path}    histogram
```

### Grafana Dashboard (shipped with Docker Compose)

```yaml
# docker-compose with monitoring
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - ./monitoring/dashboards:/var/lib/grafana/dashboards
      - ./monitoring/datasources.yml:/etc/grafana/provisioning/datasources/default.yml
      - ./monitoring/dashboard-providers.yml:/etc/grafana/provisioning/dashboards/default.yml
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

### Alert Rules

```yaml
# monitoring/alerts.yml
groups:
  - name: kalcifer
    rules:
      - alert: HighJourneyFailureRate
        expr: rate(kalcifer_journey_failures_total[5m]) / rate(kalcifer_journey_starts_total[5m]) > 0.05
        for: 5m
        annotations:
          summary: "Journey failure rate above 5%"

      - alert: HighChannelBounceRate
        expr: rate(kalcifer_channel_bounces_total[5m]) / rate(kalcifer_channel_sends_total[5m]) > 0.10
        for: 5m
        annotations:
          summary: "Channel bounce rate above 10%"

      - alert: HighMemoryUsage
        expr: kalcifer_beam_memory_bytes{type="total"} / 1024 / 1024 > 3500
        for: 5m
        annotations:
          summary: "Kalcifer memory above 3.5GB"

      - alert: SlowNodeExecution
        expr: histogram_quantile(0.99, kalcifer_node_execution_duration_ms) > 500
        for: 5m
        annotations:
          summary: "p99 node execution above 500ms"

      - alert: CrashRecoverySpike
        expr: rate(kalcifer_crash_recoveries_total[5m]) > 10
        for: 2m
        annotations:
          summary: "High crash recovery rate — possible systematic issue"
```

---

## 8. Release Process

### Versioning

Semantic versioning: `MAJOR.MINOR.PATCH`
- MAJOR: Breaking API changes
- MINOR: New features, backward compatible
- PATCH: Bug fixes, performance improvements

### Release Pipeline

```
1. PR merged to main
   → CI runs all tests (unit, integration, property)

2. Tag created (v0.3.0)
   → Full test suite including chaos + load
   → Reliability Report generated
   → Docker image built and pushed to GHCR
   → Frontend package built and published to npm
   → GitHub Release created with:
     - Changelog
     - Reliability Report
     - Docker image tag
     - Binary downloads (Linux amd64, arm64)
```

### Upgrade Path

```bash
# Docker Compose upgrade (zero-downtime)
docker compose pull kalcifer
docker compose up -d kalcifer

# Kalcifer auto-runs migrations on startup
# Ecto migrations are backward compatible (additive only)
# ClickHouse schema changes applied automatically

# Verify
curl http://localhost:4500/health/ready
```
