FROM 172.22.50.227/system_containers/alpine:3.16

LABEL maintainer="Kong <support@konghq.com>"

ARG ASSET=ce
ENV ASSET $ASSET

ARG EE_PORTS

# hadolint ignore=DL3010
COPY kong.tar.gz /tmp/kong.tar.gz

ARG KONG_VERSION=2.8.1
ENV KONG_VERSION $KONG_VERSION

ARG KONG_AMD64_SHA="ccda33bf02803b6b8dd46b22990f92265fe61d900ba94e3e0fa26db0433098c0"
ARG KONG_ARM64_SHA="d21690332a89adf9900f7266e083f41f565eb009f2771ef112f3564878eeff53"

# hadolint ignore=DL3018
RUN set -eux; \
    arch="$(apk --print-arch)"; \
    case "${arch}" in \
      x86_64) arch='amd64'; KONG_SHA256=$KONG_AMD64_SHA ;; \
      aarch64) arch='arm64'; KONG_SHA256=$KONG_ARM64_SHA ;; \
    esac; \
    if [ "$ASSET" = "ce" ] ; then \
      apk add --no-cache --virtual .build-deps curl wget tar ca-certificates \
      && curl -fL "https://download.konghq.com/gateway-${KONG_VERSION%%.*}.x-alpine/kong-$KONG_VERSION.$arch.apk.tar.gz" -o /tmp/kong.tar.gz \
      && echo "$KONG_SHA256  /tmp/kong.tar.gz" | sha256sum -c - \
      && apk del .build-deps; \
    else \
      # this needs to stay inside this "else" block so that it does not become part of the "official images" builds (https://github.com/docker-library/official-images/pull/11532#issuecomment-996219700)
      apk upgrade; \
    fi; \
    mkdir /kong \
    && tar -C /kong -xzf /tmp/kong.tar.gz \
    && mv /kong/usr/local/* /usr/local \
    && mv /kong/etc/* /etc \
    && rm -rf /kong \
    && apk add --no-cache libstdc++ libgcc openssl pcre perl tzdata libcap zip bash zlib zlib-dev git ca-certificates \
    && adduser -S kong \
    && addgroup -S kong \
    && mkdir -p "/usr/local/kong" \
    && chown -R kong:0 /usr/local/kong \
    && chown kong:0 /usr/local/bin/kong \
    && chmod -R g=u /usr/local/kong \
    && rm -rf /tmp/kong.tar.gz \
    && ln -s /usr/local/openresty/bin/resty /usr/local/bin/resty \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
    && ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && if [ "$ASSET" = "ce" ] ; then \
      kong version; \
    fi

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN luarocks install lua-resty-iputils
COPY canary /usr/local/share/lua/5.1/kong/plugins/canary
COPY file-log /usr/local/share/lua/5.1/kong/plugins/file-log
COPY http-log /usr/local/share/lua/5.1/kong/plugins/http-log
COPY loadbalance /usr/local/share/lua/5.1/kong/plugins/loadbalance
COPY api-transformer /usr/local/share/lua/5.1/kong/plugins/api-transformer
COPY prometheus /usr/local/share/lua/5.1/kong/plugins/prometheus
COPY skywalking /usr/local/share/lua/5.1/kong/plugins/skywalking
COPY url-rewrite /usr/local/share/lua/5.1/kong/plugins/url-rewrite
COPY circuit-breaker /usr/local/share/lua/5.1/kong/plugins/circuit-breaker
COPY constants.lua /usr/local/share/lua/5.1/kong/constants.lua
COPY log.lua /usr/local/share/lua/5.1/kong/pdk/log.lua

USER kong

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 $EE_PORTS

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health

CMD ["kong", "docker-start"]
