# Stage 1: Build
FROM hexpm/elixir:1.19.5-erlang-27.2-debian-bookworm-20241223-slim AS build

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*-*

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENVs
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Compile assets
COPY assets assets
COPY lib lib
COPY priv priv

# In cases where assets need to be built (uncomment if using esbuild/tailwind)
RUN mix assets.deploy

# Compile the release
RUN mix compile
RUN mix release

# Stage 2: Runtime
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && \
  apt-get install -y libsqlite3-0 libstdc++6 openssl ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*-*

WORKDIR /app
RUN chown -R nobody:nogroup /app

# Only copy the final release from the build stage
COPY --from=build --chown=nobody:nogroup /app/_build/prod/rel/w_core ./

USER nobody

# Default ENVs
ENV HOME=/app
ENV PHX_SERVER=true
ENV PORT=4000
ENV DATABASE_PATH=/data/w_core.db
ENV POOL_SIZE=10

# Create data directory for SQLite (volume mount point)
# Note: Since we are using "nobody", we need to ensure /data is writable or 
# handled via volume permissions. Usually, the user binds a local dir.

CMD ["bin/w_core", "start"]
