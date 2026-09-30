# syntax=docker/dockerfile:1
#
# Paperclip for the Railway template. The official upstream image, pinned by digest, used unmodified, plus a small
# start-up layer (images/paperclip/railway/):
#
#   start.sh            validates the template inputs, then hands over to upstream's own entrypoint
#                       (volume ownership + drop to the `node` user)
#   supervisor.sh       runs Paperclip on loopback, seeds the owner BEFORE anything listens publicly, then starts
#                       the signup gate and Caddy on $PORT
#   bootstrap-owner.mjs creates the owner account from ADMIN_EMAIL/ADMIN_PASSWORD and makes it the instance admin
#                       through Paperclip's own bootstrap-invite flow (the same one `paperclipai auth bootstrap-ceo`
#                       uses)
#   signup-gate.mjs     Caddy forward_auth target: sign-up is allowed only from a live invitation link
#   Caddyfile           the public front door
#
# Not affiliated with the Paperclip project.
ARG PAPERCLIP_IMAGE=ghcr.io/paperclipai/paperclip:2026.916.1@sha256:a02ac35ac41df911af477422ea0e781cf41d2b2c600c66f0a5ac9d8c63f52c2c
ARG CADDY_IMAGE=docker.io/library/caddy:2.10.2@sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb

FROM ${CADDY_IMAGE} AS caddy

FROM ${PAPERCLIP_IMAGE}
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY images/paperclip/railway/ /opt/paperclip-railway/
RUN chmod 0755 /opt/paperclip-railway/start.sh /opt/paperclip-railway/supervisor.sh \
  && chmod 0644 /opt/paperclip-railway/*.mjs /opt/paperclip-railway/Caddyfile \
  && PORT=3100 PAPERCLIP_INTERNAL_PORT=3101 PAPERCLIP_GATE_PORT=3102 \
     caddy validate --adapter caddyfile --config /opt/paperclip-railway/Caddyfile

# Internet-facing defaults. Paperclip itself listens on 127.0.0.1:$PAPERCLIP_INTERNAL_PORT; only Caddy is public.
ENV PAPERCLIP_DEPLOYMENT_MODE=authenticated \
    PAPERCLIP_DEPLOYMENT_EXPOSURE=public \
    PAPERCLIP_MIGRATION_AUTO_APPLY=true \
    PAPERCLIP_SIGNUP_MODE=invite-only \
    PAPERCLIP_INTERNAL_PORT=3101 \
    PAPERCLIP_GATE_PORT=3102 \
    PORT=3100 \
    TRUST_PROXY=loopback \
    XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

LABEL org.opencontainers.image.title="paperclip-railway" \
      org.opencontainers.image.description="Paperclip for the Railway template: the official image pinned by digest, owner seeded, sign-up invite-only. Not affiliated with the Paperclip project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/paperclip-railway" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

EXPOSE 3100
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/paperclip-railway/start.sh"]
CMD []
