# ==============================================================================
# Personal Caddy Reverse Proxy Wrapper Image
# ==============================================================================

# renovate: datasource=docker depName=caddy
ARG CADDY_VERSION="2.11.4-alpine"

FROM caddy:${CADDY_VERSION}

LABEL org.opencontainers.image.title="Personal Caddy Reverse Proxy"
LABEL org.opencontainers.image.description="Opinionated non-root Caddy reverse proxy image for homelab deployments."
LABEL org.opencontainers.image.source="https://github.com/andygodish/image-caddy"

ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

RUN mkdir -p /config/caddy /data/caddy && \
    chown -R 10005:10005 /config /data /etc/caddy

COPY --chown=10005:10005 Caddyfile.example /etc/caddy/Caddyfile
COPY --chown=10005:10005 version.txt /usr/local/share/version.txt

USER 10005:10005

VOLUME ["/config", "/data"]

EXPOSE 8080 8443
