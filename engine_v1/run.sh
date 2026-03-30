#!/bin/bash

# Configurações de Ambiente para W-Core (MacOS Restricted)
export MIX_HOME="/Users/apple/w_core/engine_v1/mix_home"
export HEX_HOME="/Users/apple/w_core/engine_v1/hex_home"
export MIX_DEPS_PATH="/Users/apple/w_core/engine_v1/deps_data"
export MIX_BUILD_PATH="/Users/apple/w_core/engine_v1/build_data"
export ELIXIR_MAKE_CACHE_DIR="/Users/apple/w_core/engine_v1/elixir_make_cache"
export TMPDIR="/Users/apple/w_core/tmp"

# Carregar Homebrew se disponível (necessário para o Elixir do sistema se usado)
eval "$(/opt/homebrew/bin/brew shellenv)"

cd /Users/apple/w_core/engine_v1

echo "--- W-CORE: INICIANDO MOTOR INDUSTRIAL ---"
echo "Banco de Dados: /tmp/w_core_dev.db"
echo "URL: http://localhost:4000"
echo "------------------------------------------"

# Iniciar servidor Phoenix
mix phx.server
