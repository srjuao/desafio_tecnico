# Step 4 — Simulação de Caos

## O que foi implementado

- `TelemetryCase`: case base que isola ETS e GenServers por teste.
- Testes unitários do TelemetryServer (inserção, contagem, PubSub).
- Testes unitários do WriteWorker (sync, upsert, idempotência).
- Teste de caos: 10.000 eventos concorrentes via Task.async_stream.

## Como provamos a ausência de race condition

O `update_counter` do ETS é atômico no nível do BEAM scheduler.
Mesmo com 10 processos incrementando simultaneamente, o contador
final é exatamente N × 1000. Se houvesse race condition do tipo
read-modify-write, o contador seria menor — a contagem no teste
detecta isso imediatamente.

## Por que :sys.get_state em vez de :timer.sleep?

`TelemetryServer.ingest` usa `cast` (assíncrono). Para garantir que
todos os casts foram processados antes das asserções, fazemos um
`call` síncrono via `:sys.get_state`. Um call só retorna quando o
GenServer processou todos os casts anteriores da sua fila — é uma
barreira de sincronização determinística, sem depender de timers.

## Resultado do teste de caos

- 10 nodes × 1.000 eventos = 10.000 eventos totais.
- ETS: 10 nodes, cada um com count = 1.000 ✓
- SQLite: 10 métricas, status e contagem corretos ✓
- Crash recovery: SQLite preservou estado após reinício do GenServer ✓
