FROM alpine:3.21

RUN apk add --no-cache \
      bash \
      iproute2 \
      netcat-openbsd \
      openssh-server \
      python3

COPY docker/onboarding-test/fake-node/bin/uci /usr/local/bin/uci
COPY docker/onboarding-test/fake-node/bin/ubus /usr/local/bin/ubus
COPY docker/onboarding-test/fake-node/bin/bmx7 /usr/local/bin/bmx7
COPY docker/onboarding-test/fake-node/bin/iwinfo /usr/local/bin/iwinfo
COPY docker/onboarding-test/fake-node/bin/ip /usr/local/bin/ip
COPY docker/onboarding-test/fake-node/entrypoint.sh /usr/local/bin/fake-node-entrypoint.sh

RUN chmod +x \
      /usr/local/bin/uci \
      /usr/local/bin/ubus \
      /usr/local/bin/bmx7 \
      /usr/local/bin/iwinfo \
      /usr/local/bin/ip \
      /usr/local/bin/fake-node-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/fake-node-entrypoint.sh"]
