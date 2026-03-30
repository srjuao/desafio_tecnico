# Step 5 — Docker & Empacotamento (Edge Registry)

## O que foi implementado

- `Dockerfile`: Imagem multi-stage otimizada (Build em Debian, Runtime em Slim).
- `docker-compose.yml`: Orquestração simples com volume persistente para SQLite.
- Configuração de Release: Uso de `mix release` para gerar um binário autocontido.

## Estratégia de Deploy no Edge

Para plantas industriais, o deploy deve ser resiliente. A imagem gerada contém:
1. **Runtime Erlang/OTP Completo**: Sem necessidade de instalar Elixir no host.
2. **SQLite Integrado**: Banco de dados via arquivo, montado em `/data` para persistência entre restarts do container.
3. **Segurança**: Processo rodando como usuário `nobody` (non-root).

## Como rodar em Produção

```bash
# 1. Gerar Secret Key
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# 2. Subir container
docker-compose up -d --build
```

## Benefícios da Release Elixir

Diferente de rodar com `mix phx.server`, a release pré-compila os arquivos BEAM, otimiza o carregamento de módulos e remove ferramentas de desenvolvimento, resultando em um boot mais rápido e menor pegada de memória — essencial para dispositivos Edge com recursos limitados.
