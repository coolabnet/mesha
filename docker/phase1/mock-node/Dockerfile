FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        iproute2 \
        netcat-openbsd \
        openssh-server \
        procps \
        python3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /fixtures /var/www/mock

COPY docker/phase1/mock-node/bin/uci /usr/local/bin/uci
COPY docker/phase1/mock-node/bin/ubus /usr/local/bin/ubus
COPY docker/phase1/mock-node/bin/iwinfo /usr/local/bin/iwinfo
COPY docker/phase1/mock-node/bin/bmx7 /usr/local/bin/bmx7
COPY docker/phase1/mock-node/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/phase1/fixtures/ /fixtures/

RUN chmod +x /usr/local/bin/uci \
    /usr/local/bin/ubus \
    /usr/local/bin/iwinfo \
    /usr/local/bin/bmx7 \
    /usr/local/bin/entrypoint.sh

EXPOSE 22 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
