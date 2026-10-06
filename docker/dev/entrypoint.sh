#!/usr/bin/env bash
# Punto de entrada del contenedor de desarrollo.
#   server  → prepara dependencias y base, y levanta Phoenix con recarga en vivo.
#   otro    → ejecuta el comando tal cual (mix test, bash, etc.).
set -euo pipefail

prepare() {
  mix deps.get
  mix assets.setup
  # Espera a que PostgreSQL acepte conexiones antes de migrar.
  until pg_isready -h "${DATABASE_HOST:-db}" -U "${DATABASE_USER:-postgres}" -q; do
    echo "Esperando a PostgreSQL…"
    sleep 1
  done
  mix ecto.create
  mix ecto.migrate
}

if [ "${1:-server}" = "server" ]; then
  prepare
  # Nodo con nombre para poder conectarse con `iex --remsh` (bin/dev iex).
  exec elixir --sname amauta --cookie "${ERLANG_COOKIE:-amauta-dev}" -S mix phx.server
fi

exec "$@"
