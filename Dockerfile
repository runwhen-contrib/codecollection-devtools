###############################################################################
# CodeCollection DevTools
#
# Development environment for authoring and testing RunWhen codebundles.
# Built on the slim base image (Python + worker + runtime + rw-core-keywords).
# Adds ALL common CLI tools since authors may develop for any platform.
#
# rw-core-keywords handles both dev and production modes — no separate
# dev_facade needed. Set RW_MODE=dev (default in this image) for local
# development behavior.
###############################################################################

ARG BASE_IMAGE=us-docker.pkg.dev/runwhen-nonprod-shared/public-images/robot-runtime-base-image:latest
FROM ${BASE_IMAGE}

USER root

ENV RUNWHEN_HOME=/home/runwhen
ENV ROBOT_LOG_DIR=/robot_logs
ENV RW_MODE=dev

# Ensure runwhen user has a fixed UID/GID (1000) for volume mounts
RUN usermod -u 1000 runwhen && \
    groupmod -g 1000 runwhen

###############################################################################
# Dev tools: sudo, gpg/apt deps (bookworm+ has HTTPS in apt; skip apt-transport-https)
# Base image (robot-runtime-base) already ships: curl, ca-certificates, wget, unzip.
# Apt under QEMU (arm64 on amd64 CI) often exits 100 without Pipeline-Depth=0 + retries.
###############################################################################
ENV DEBIAN_FRONTEND=noninteractive
RUN printf '%s\n' \
      'Acquire::http::Pipeline-Depth "0";' \
      'Acquire::https::Pipeline-Depth "0";' \
      'Acquire::Retries "5";' \
      'Acquire::http::Timeout "120";' \
      'Acquire::https::Timeout "120";' \
    > /etc/apt/apt.conf.d/99docker-ci \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gnupg \
        lsb-release \
        sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN echo "runwhen ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Architecture detection for multi-arch tool installs
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        echo "ARCH_BIN=amd64" >> /tmp/arch_vars; \
        echo "AWS_ARCH=x86_64" >> /tmp/arch_vars; \
    elif [ "$ARCH" = "aarch64" ]; then \
        echo "ARCH_BIN=arm64" >> /tmp/arch_vars; \
        echo "AWS_ARCH=aarch64" >> /tmp/arch_vars; \
    else \
        echo "Unsupported architecture: $ARCH"; exit 1; \
    fi

# go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Terraform
ENV TERRAFORM_VERSION=1.11.2
RUN . /tmp/arch_vars && \
    wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH_BIN}.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_${ARCH_BIN}.zip terraform -d /usr/local/bin/ && \
    rm terraform_${TERRAFORM_VERSION}_linux_${ARCH_BIN}.zip

###############################################################################
# CLI tools — all common tools for multi-platform codebundle development
###############################################################################

# kubectl
RUN . /tmp/arch_vars && \
    curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_BIN}/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin

# Helm
RUN . /tmp/arch_vars && \
    HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name') && \
    curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH_BIN}.tar.gz" && \
    tar -zxvf /tmp/helm.tar.gz -C /tmp && \
    mv /tmp/linux-${ARCH_BIN}/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /tmp/helm.tar.gz /tmp/linux-${ARCH_BIN}

# AWS CLI
RUN . /tmp/arch_vars && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && ./aws/install --update && \
    rm -rf awscliv2.zip ./aws

# Azure CLI
RUN . /tmp/arch_vars && \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null && \
    echo "deb [arch=${ARCH_BIN}] https://packages.microsoft.com/repos/azure-cli/ bookworm main" | tee /etc/apt/sources.list.d/azure-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends azure-cli && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# kubelogin (Azure AKS)
RUN . /tmp/arch_vars && \
    curl -Lo kubelogin.zip https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-${ARCH_BIN}.zip && \
    unzip kubelogin.zip && mv bin/linux_${ARCH_BIN}/kubelogin /usr/local/bin/ && \
    rm -rf kubelogin.zip bin && chmod +x /usr/local/bin/kubelogin

# Google Cloud SDK
ARG CLOUD_SDK_VERSION=532.0.0
RUN . /tmp/arch_vars && \
    if [ "$ARCH_BIN" = "amd64" ]; then GCLOUD_ARCH="x86_64"; else GCLOUD_ARCH="arm"; fi && \
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${CLOUD_SDK_VERSION}-linux-${GCLOUD_ARCH}.tar.gz && \
    tar xzf google-cloud-cli-${CLOUD_SDK_VERSION}-linux-${GCLOUD_ARCH}.tar.gz && \
    rm google-cloud-cli-${CLOUD_SDK_VERSION}-linux-${GCLOUD_ARCH}.tar.gz && \
    rm -rf google-cloud-sdk/platform/bundledpythonunix
ENV PATH="${RUNWHEN_HOME}/google-cloud-sdk/bin:$PATH"
RUN gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true && \
    gcloud components update --quiet && \
    gcloud components install -q beta gke-gcloud-auth-plugin && \
    rm -rf $(find google-cloud-sdk/ -regex ".*/__pycache__") \
           google-cloud-sdk/.install/.backup \
           google-cloud-sdk/bin/anthoscli

# istioctl
RUN . /tmp/arch_vars && \
    ISTIO_VERSION="$(curl -s https://api.github.com/repos/istio/istio/releases/latest | jq -r '.tag_name')" && \
    curl -fsSL -o /tmp/istioctl.tar.gz \
      "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-${ARCH_BIN}.tar.gz" && \
    tar -xzf /tmp/istioctl.tar.gz -C /tmp && \
    mv /tmp/istioctl /usr/local/bin/ && chmod +x /usr/local/bin/istioctl && \
    rm /tmp/istioctl.tar.gz

# GitHub CLI (PR checkout in devcontainer)
RUN . /tmp/arch_vars && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=${ARCH_BIN} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Cleanup
RUN rm -f /tmp/arch_vars

###############################################################################
# Dev environment setup
###############################################################################

WORKDIR $RUNWHEN_HOME

RUN mkdir -p $ROBOT_LOG_DIR && \
    chown runwhen:0 $ROBOT_LOG_DIR && \
    chmod 775 $ROBOT_LOG_DIR

COPY --chown=runwhen:0 .pylintrc.google LICENSE ro requirements.txt .
COPY --chown=runwhen:0 .devcontainer/ .devcontainer/
RUN mkdir -p auth && \
    chown -R runwhen:0 ${RUNWHEN_HOME}/.devcontainer ${RUNWHEN_HOME}/auth && \
    chmod -R 0775 ${RUNWHEN_HOME}/ro ${RUNWHEN_HOME}/auth ${RUNWHEN_HOME}/.devcontainer

USER runwhen
ENV USER="runwhen"

RUN pip install --user --no-cache-dir -r requirements.txt

ENV PATH="${PATH}:/usr/local/bin:${RUNWHEN_HOME}/.local/bin:${RUNWHEN_HOME}"
ENV PYTHONPATH="$PYTHONPATH:.:${RUNWHEN_HOME}/codecollection/libraries:${RUNWHEN_HOME}/codecollection/codebundles"

EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
