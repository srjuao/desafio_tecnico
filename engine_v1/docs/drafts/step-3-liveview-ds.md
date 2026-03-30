# Step 3 — LiveView & Design System

## O que foi implementado

- `PlantComponents`: design system HEEx com status_badge,
  machine_card e stat_card.
- `DashboardLive`: dashboard em tempo real protegido por autenticação.
- Flash visual para status critical com limpeza automática após 1500ms.
- Estatísticas agregadas reativas (total, ok, warning, critical).

## Arquitetura de leitura
```mermaid
sequenceDiagram
  participant Sensor
  participant TelemetryServer
  participant ETS
  participant PubSub
  participant DashboardLive

  Sensor->>TelemetryServer: cast :ingest
  TelemetryServer->>ETS: update_element + update_counter
  TelemetryServer->>PubSub: broadcast (só se status mudou)
  PubSub->>DashboardLive: handle_info :node_status_changed
  DashboardLive->>ETS: Cache.get(node_id) — leitura pontual
  DashboardLive->>DashboardLive: assign + re-render parcial
```
