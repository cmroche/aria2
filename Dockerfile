ARG DEBIAN_VERSION=bookworm
ARG ARIA2_VERSION=1.37.0
ARG ARIA2_SHA256=60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b

FROM debian:${DEBIAN_VERSION}-slim AS builder

ARG ARIA2_VERSION
ARG ARIA2_SHA256
ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        libc-ares-dev \
        libsqlite3-dev \
        libssh2-1-dev \
        libssl-dev \
        libxml2-dev \
        pkg-config \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

RUN curl -fsSLO "https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.xz" \
    && echo "${ARIA2_SHA256}  aria2-${ARIA2_VERSION}.tar.xz" | sha256sum -c - \
    && tar -xf "aria2-${ARIA2_VERSION}.tar.xz" \
    && cd "aria2-${ARIA2_VERSION}" \
    && ./configure \
        --prefix=/usr/local \
        --disable-bittorrent \
        --enable-metalink \
        --enable-websocket \
        --with-openssl \
        --without-gnutls \
        --with-libcares \
        --with-libssh2 \
        --with-libxml2 \
        --with-sqlite3 \
        --with-libz \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
    && make -j"$(nproc)" \
    && make install \
    && mkdir -p /licenses/aria2 \
    && cp COPYING AUTHORS README.rst /licenses/aria2/

FROM debian:${DEBIAN_VERSION}-slim AS runtime

ARG ARIA2_VERSION
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="aria2 TrueNAS Custom App" \
      org.opencontainers.image.description="aria2 compiled without BitTorrent support for TrueNAS Custom App deployments." \
      org.opencontainers.image.source="https://github.com/cmroche/aria2" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.version="${ARIA2_VERSION}"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gosu \
        libc-ares2 \
        libsqlite3-0 \
        libssh2-1 \
        libssl3 \
        libstdc++6 \
        libxml2 \
        tzdata \
        zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 568 apps \
    && useradd \
        --uid 568 \
        --gid 568 \
        --home-dir /nonexistent \
        --shell /usr/sbin/nologin \
        --no-create-home \
        apps \
    && mkdir -p /downloads \
    && chown 568:568 /downloads

COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c
COPY --from=builder /licenses/aria2 /usr/share/doc/aria2
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

ENV DOWNLOAD_DIR=/downloads \
    RPC_PORT=6800 \
    ARIA2_LOG_LEVEL=notice \
    TZ=Etc/UTC

VOLUME ["/downloads"]
EXPOSE 6800/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
