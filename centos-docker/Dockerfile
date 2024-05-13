FROM centos:8
LABEL maintainer="Kong <support@konghq.com>"

ARG ASSET=ce
ENV ASSET $ASSET

ARG EE_PORTS

COPY kong.rpm /tmp/kong.rpm
COPY Centos-vault-8.5.2111.repo /etc/yum.repos.d/CentOS-Base.repo

ARG KONG_VERSION=2.8.1
ENV KONG_VERSION $KONG_VERSION

ARG KONG_SHA256="95422738b65f8700823bf873bedab695973b17e3b67a117e524aeaa55d09f043"

# hadolint ignore=DL3033
RUN set -ex; \
    if [ "$ASSET" = "ce" ] ; then \
      curl -fL https://download.konghq.com/gateway-${KONG_VERSION%%.*}.x-centos-8/Packages/k/kong-$KONG_VERSION.el8.amd64.rpm -o /tmp/kong.rpm; \

    fi; \

    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* \
    # 将 mirror.centos.org 改成 vault.centos.org
    && sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*  \
   # && wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo    \
    && yum clean all \
    && yum makecache \
    && yum install -y -q unzip shadow-utils git gcc \
    && yum clean all -q \
    && rm -fr /var/cache/yum/* /tmp/yum_save*.yumtx /root/.pki \
    # Please update the centos install docs if the below line is changed so that
    # end users can properly install Kong along with its required dependencies
    # and that our CI does not diverge from our docs.
    && yum install -y /tmp/kong.rpm \
    && yum clean all \
    && rm /tmp/kong.rpm \
    && chown kong:0 /usr/local/bin/kong \
    && chown -R kong:0 /usr/local/kong \
    && ln -s /usr/local/openresty/bin/resty /usr/local/bin/resty \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
    && ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && if [ "$ASSET" = "ce" ] ; then \
      kong version ; \
    fi

COPY docker-entrypoint.sh /docker-entrypoint.sh
#RUN luarocks install luaossl CRYPTO_DIR=/usr/local/kong OPENSSL_DIR=/usr/local/kong
#RUN /usr/local/openresty/bin/opm get leafo/pgmoon
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
#COPY round_robin.lua /usr/local/share/lua/5.1/kong/runloop/balancer/round_robin.lua
#COPY grpc-gateway /usr/local/share/lua/5.1/kong/plugins/grpc-gateway
#COPY grpc.lua /usr/local/share/lua/5.1/kong/tools/grpc.lua
#COPY protoc.lua /usr/local/share/lua/5.1/protoc.lua
USER kong

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 $EE_PORTS

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health

CMD ["kong", "docker-start"]
