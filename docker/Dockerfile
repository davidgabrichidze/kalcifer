# Stage 1: Build
FROM elixir:1.18-otp-28-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app
ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Copy application code
COPY config config
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

# Stage 2: Runtime
FROM alpine:3.22 AS runner

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/kalcifer ./

ENV PHX_HOST=localhost

EXPOSE 4500

CMD ["bin/kalcifer", "start"]
