# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian instead of
# Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20210902-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.13.4-erlang-24.0.1-debian-bullseye-20210902-slim
#
ARG ELIXIR_VERSION=1.14.2
ARG OTP_VERSION=25.1.2
ARG ALPINE_VERSION=3.17.0

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
# ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies
RUN apk add --no-cache build-base git

# prepare build dir
WORKDIR /app

# extend hex timeout
ENV HEX_HTTP_TIMEOUT=20

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV EXS_DRY_RUN="true"
ENV MIX_INSTALL_DIR="/app/.mix"

# install mix dependencies
COPY run.exs ./
RUN elixir ./run.exs

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# install build dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"
ENV MIX_INSTALL_DIR="/app/.mix"
ENV SHELL=/bin/bash
ENV ERL_AFLAGS "-proto_dist inet6_tcp"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/.mix/ ./.mix
COPY --from=builder --chown=nobody:root /app/run.exs ./

RUN mix local.hex --force && \
    mix local.rebar --force

CMD ["elixir", "/app/run.exs"]

