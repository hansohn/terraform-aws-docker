ARG TERRAFORM_VERSION=latest


# builder
FROM hansohn/terraform:${TERRAFORM_VERSION} AS builder
ARG TFLINT_VERSION=latest
COPY dotfiles/. /root/
ENV CURL='curl -fsSL --netrc-optional'
RUN apt-get update && apt-get install --no-install-recommends -y \
      bash \
      ca-certificates \
      curl \
      jq \
      libc6 \
      unzip

# tflint
RUN /bin/bash -c 'TFLINT_AWS_VERSION=$(${CURL} "https://api.github.com/repos/terraform-linters/tflint-ruleset-aws/releases/latest" | jq -r .tag_name | sed -e "s:^v::") \
      && sed -ie "s:TFLINT_AWS_VERSION:$TFLINT_AWS_VERSION:" /root/.tflint.hcl \
      && GITHUB_TOKEN=${GITHUB_TOKEN:-$(awk "'"c&&!--c;/github.com/{c=2}"'" /root/.netrc | awk "'"{print $2;exit}"'")} \
      && tflint --version \
      && tflint --init'

# awscli
RUN /bin/bash -c 'ARCH=$(uname -m) \
      && ${CURL} https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip -o /tmp/awscliv2.zip \
      && cd /tmp \
      && unzip awscliv2.zip \
      && ./aws/install --bin-dir /aws-cli-bin/ \
      && /aws-cli-bin/aws --version'


# main
FROM hansohn/terraform:${TERRAFORM_VERSION} AS main
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install --no-install-recommends -y \
      bash \
      curl \
      ca-certificates \
      git \
      groff \
      jq \
      unzip \
      vim \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/*
COPY --from=builder /aws-cli-bin/ /usr/local/bin/
COPY --from=builder /root/.tflint.d/. /root/.tflint.d/
COPY --from=builder /root/.tflint.hcl /root/
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=builder /usr/local/bin/ /usr/local/bin/
RUN /bin/bash -c 'terraform --version'
RUN printf '\ncomplete -C /usr/local/bin/aws_completer aws\n' >> /root/.bashrc

ENTRYPOINT []
