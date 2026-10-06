# Imagen de desarrollo de Amauta: Elixir, Erlang, Node y herramientas.
# El código no se copia: se monta desde el host (RNF-DEV-002).
ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-28.5.0.7-debian-trixie-20260918-slim

FROM ${ELIXIR_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates inotify-tools \
      postgresql-client nodejs npm locales tini \
 && rm -rf /var/lib/apt/lists/*

# En hosts Linux se usa el UID y GID del usuario para no dejar archivos
# con dueño root en el bind mount (RNF-DEV-010). En Windows no influye.
ARG UID=1000
ARG GID=1000
RUN groupadd --gid ${GID} dev \
 && useradd --uid ${UID} --gid ${GID} --create-home --shell /bin/bash dev

ENV MIX_HOME=/home/dev/.mix \
    HEX_HOME=/home/dev/.hex \
    ERL_AFLAGS="-kernel shell_history enabled"

# Los puntos de montaje de los volúmenes nombrados se crean acá para que
# Docker los inicialice con el dueño correcto (RNF-DEV-003).
RUN mkdir -p /app/deps /app/_build /app/assets/node_modules \
      /home/dev/.mix /home/dev/.hex /home/dev/.cache \
 && chown -R dev:dev /app /home/dev

USER dev
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# El punto de entrada se ejecuta desde el código montado: editarlo no
# requiere reconstruir la imagen.
ENTRYPOINT ["tini", "--", "bash", "/app/docker/dev/entrypoint.sh"]
CMD ["server"]
