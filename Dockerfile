FROM ghcr.io/actions/actions-runner:2.336.0

ARG TARGETARCH
ARG DOCKER_COMPOSE_VERSION=5.4.0

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        libssl-dev \
        openssh-client \
        openssl \
        pkg-config \
        python3 \
        rsync \
        shellcheck \
        zstd \
    && rm -rf /var/lib/apt/lists/* \
    && case "${TARGETARCH}" in \
        amd64) compose_arch="x86_64" ;; \
        arm64) compose_arch="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && install -d -m 0755 /usr/local/lib/docker/cli-plugins \
    && curl -fsSL \
        "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose \
    && docker compose version \
    && install -d -o runner -g docker -m 0755 \
        /home/runner/.rustup \
        /home/runner/.cache \
        /home/runner/.cache/pnpm \
        /home/runner/.cache/argus \
        /home/runner/.cache/argus/cargo-home \
        /home/runner/.cache/argus/cargo-target \
        /home/runner/.cache/argus/pnpm

COPY --chown=runner:docker entrypoint.sh /usr/local/bin/argus-runner-entrypoint
RUN chmod 0755 /usr/local/bin/argus-runner-entrypoint

USER runner
WORKDIR /home/runner

ENTRYPOINT ["/usr/local/bin/argus-runner-entrypoint"]
