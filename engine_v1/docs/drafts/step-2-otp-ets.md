# Step 2 — OTP & ETS: O Coração da Usina

## O que foi implementado

- `TelemetryServer`: GenServer que recebe eventos e grava no ETS
- `WriteWorker`: GenServer com timer periódico que sincroniza ETS → SQLite
- `TelemetrySupervisor`: Supervisor :one_for_one supervisionando ambos
- `Cache`: wrapper de leitura do ETS
- `HeartbeatController`: endpoint HTTP para receber pulsos dos sensores

## Arquitetura atual
```mermaid
graph TD
  S[Sensor] -->|POST /api/heartbeat| H[HeartbeatController]
  H -->|cast :ingest| TS[TelemetryServer]
  TS -->|:ets.insert / update_element| ETS[(:w_core_telemetry_cache)]
  TS -->|PubSub.broadcast se status mudou| PS[Phoenix.PubSub]
  WW[WriteWorker] -->|lê a cada 5s| ETS
  WW -->|upsert em lote| DB[(SQLite)]
  PS -->|notifica| LV[LiveView — Passo 3]
```

## Decisões técnicas

### Tipo de tabela ETS: :set com :named_table e read_concurrency: true
- `:set` garante uma entrada por node_id.
- `read_concurrency: true` otimiza leituras paralelas.

### Por que :ets.update_counter e não :ets.insert?
`update_counter` é uma operação atômica no nível do BEAM — elimina race conditions de incremento.

### Por que só broadcast no PubSub quando o status muda?
Evita flood de mensagens e re-renders inúteis se o estado do sensor for estável.

### Estratégia de supervisão: :one_for_one
Isolamento de falhas entre ingestão (ETS) e persistência (SQLite).
