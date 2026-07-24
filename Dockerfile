# renovate: datasource=docker depName=hansohn/terraform
ARG TERRAFORM_VERSION=1.15.7


# builder
FROM hansohn/terraform:${TERRAFORM_VERSION} AS builder
ARG DEBIAN_FRONTEND=noninteractive
# renovate: datasource=github-releases depName=terraform-linters/tflint-ruleset-aws extractVersion=^v(?<version>.+)$
ARG TFLINT_AWS_VERSION=0.48.0
# renovate: datasource=github-tags depName=aws/aws-cli
ARG AWSCLI_VERSION=2.36.7
# AWS CLI installer packages are PGP-signed by the AWS CLI Team key. Trust is
# pinned to this fingerprint; the current public key (with up-to-date expiry) is
# fetched from a keyserver at build time so extensions don't require a rebuild.
ARG AWSCLI_GPG_FINGERPRINT=FB5DB77FD5C118B80511ADA8A6310ACC4672475C
ENV CURL='curl -fsSL'
ENV CACHE_DIR='/var/cache/github-api'
COPY scripts/resolve-version.sh /opt/build/resolve-version
COPY config/.tflint.hcl /root/.tflint.hcl
RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates \
      curl \
      dirmngr \
      gnupg \
      jq \
      unzip \
  && mkdir -p ${CACHE_DIR} \
  && rm -rf /var/lib/apt/lists/*

# tflint-ruleset-aws
# Installed directly as a manually-managed plugin (no `tflint --init`), so the
# build never reaches out to the GitHub API at lint time and the version is
# pinned and checksum-verified here.
RUN --mount=type=cache,target=/var/cache/github-api \
    --mount=type=cache,target=/var/cache/downloads \
    /bin/bash -c 'set -e; \
  TFLINT_AWS_VERSION=$(/opt/build/resolve-version tflint-ruleset-aws "${TFLINT_AWS_VERSION}"); \
  case "$(uname -m)" in \
    x86_64) ARCH=amd64 ;; \
    aarch64) ARCH=arm64 ;; \
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
  esac; \
  ARCHIVE="tflint-ruleset-aws_linux_${ARCH}.zip"; \
  if [[ ! -f "/var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}-${ARCH}.zip" ]]; then \
  ${CURL} https://github.com/terraform-linters/tflint-ruleset-aws/releases/download/v${TFLINT_AWS_VERSION}/${ARCHIVE} -o /var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}-${ARCH}.zip; \
  fi; \
  if [[ ! -f "/var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}_checksums.txt" ]]; then \
  ${CURL} https://github.com/terraform-linters/tflint-ruleset-aws/releases/download/v${TFLINT_AWS_VERSION}/checksums.txt -o /var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}_checksums.txt; \
  fi; \
  EXPECTED_SHA=$(grep " ${ARCHIVE}\$" /var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}_checksums.txt | cut -d" " -f1); \
  ACTUAL_SHA=$(sha256sum /var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}-${ARCH}.zip | cut -d" " -f1); \
  if [[ -z "${EXPECTED_SHA}" ]] || [[ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]]; then \
  echo "Checksum verification failed for ${ARCHIVE}" >&2; exit 1; \
  fi; \
  mkdir -p /root/.tflint.d/plugins; \
  unzip -o /var/cache/downloads/tflint-ruleset-aws-${TFLINT_AWS_VERSION}-${ARCH}.zip -d /root/.tflint.d/plugins \
  && chmod +x /root/.tflint.d/plugins/tflint-ruleset-aws \
  && tflint --version'

# awscli
RUN --mount=type=cache,target=/var/cache/github-api \
    --mount=type=cache,target=/var/cache/downloads \
    /bin/bash -c 'set -e; \
  AWSCLI_VERSION=$(/opt/build/resolve-version aws-cli "${AWSCLI_VERSION}"); \
  ARCH=$(uname -m); \
  ZIP="/var/cache/downloads/awscli-${AWSCLI_VERSION}-${ARCH}.zip"; \
  SIG="/var/cache/downloads/awscli-${AWSCLI_VERSION}-${ARCH}.zip.sig"; \
  if [[ ! -f "${ZIP}" ]]; then \
  ${CURL} https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}-${AWSCLI_VERSION}.zip -o "${ZIP}"; \
  fi; \
  if [[ ! -f "${SIG}" ]]; then \
  ${CURL} https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}-${AWSCLI_VERSION}.zip.sig -o "${SIG}"; \
  fi; \
  export GNUPGHOME="$(mktemp -d)"; \
  for ks in keyserver.ubuntu.com keys.openpgp.org pgp.mit.edu; do \
  gpg --batch --keyserver "hkps://${ks}" --recv-keys "${AWSCLI_GPG_FINGERPRINT}" && break; \
  done; \
  gpg --batch --verify "${SIG}" "${ZIP}"; \
  gpgconf --kill all || true; \
  rm -rf "${GNUPGHOME}"; \
  unzip -q -o "${ZIP}" -d /tmp; \
  /tmp/aws/install --bin-dir /aws-cli-bin/ --install-dir /usr/local/aws-cli \
  && /aws-cli-bin/aws --version'


# main
FROM hansohn/terraform:${TERRAFORM_VERSION} AS main
ARG DEBIAN_FRONTEND=noninteractive
# awscli renders help output through groff/less; install them so `aws help` works.
RUN apt-get update && apt-get install --no-install-recommends -y \
      groff \
      less \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
COPY --from=builder /aws-cli-bin/ /usr/local/bin/
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=builder /root/.tflint.d/ /root/.tflint.d/
COPY --from=builder /root/.tflint.hcl /root/.tflint.hcl
RUN printf '\ncomplete -C /usr/local/bin/aws_completer aws\n' >> /root/.bashrc \
  && aws --version \
  && terraform --version

ENTRYPOINT []
