# Build stage
FROM elixir:1.15-alpine AS build

RUN apk add --no-cache build-base git
WORKDIR /app

# Install deps
COPY mix.exs mix.lock ./
COPY config config
RUN MIX_ENV=prod mix deps.get --only prod

# Copy source and build assets + release
COPY . .
RUN MIX_ENV=prod mix assets.deploy
RUN MIX_ENV=prod mix release

# Runtime stage
FROM alpine:3.19 AS app
# libstdc++ fixes "__gxx_personality_v0" at runtime for beam.smp
RUN apk add --no-cache openssl ncurses-libs libstdc++
WORKDIR /app
COPY --from=build /app/_build/prod/rel/chord_sim ./
ENV HOME=/app

# ERL_COOKIE, RELEASE_NODE, RELEASE_DISTRIBUTION, PORT, PHX_HOST can be set at runtime
CMD ["bin/chord_sim", "start"]
