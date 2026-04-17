# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Mesha Community Infrastructure Project
# Licensed under the MIT License; see LICENSE file for details.
FROM node:22-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY docker/onboarding-test/ops/entrypoint.sh /opt/mesha-test/ops-entrypoint.sh
COPY docker/onboarding-test/phase1-test.sh /opt/mesha-test/phase1-test.sh

RUN chmod +x /opt/mesha-test/ops-entrypoint.sh /opt/mesha-test/phase1-test.sh

ENTRYPOINT ["/opt/mesha-test/ops-entrypoint.sh"]
CMD ["sleep", "infinity"]
