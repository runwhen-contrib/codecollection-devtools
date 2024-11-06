FROM gitpod/workspace-full

ENV WORKDIR /workspace/codecollection-devtools
ENV python_version 3.12.6
ENV ROBOT_LOG_DIR /workspace/robot_logs


RUN mkdir -p $WORKDIR
WORKDIR $WORKDIR

USER root
# Install and validate kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
RUN echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
RUN rm kubectl.sha256
RUN chmod +x kubectl
RUN mv kubectl /usr/local/bin/

# Install Helm CLI
RUN HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name') \
    && curl -fsSL -o /tmp/helm.tar.gz https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
    && tar -zxvf /tmp/helm.tar.gz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 

# Download and install the latest version of yq
RUN curl -Lo /usr/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    && chmod +x /usr/bin/yq

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash


# Install packages
RUN apt-get update && \
    apt install -y jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/cache/apt

COPY . .

# Robotframework setup
RUN pyenv install $python_version
RUN pyenv global 3.12
ENV PYTHONPATH "$PYTHONPATH:.:$WORKDIR/rw-public-codecollection/libraries:$WORKDIR/rw-public-codecollection/codebundles:$WORKDIR/codecollection/libraries:$WORKDIR/codecollection/codebundles:$WORKDIR/dev_facade"

ENV PATH "$PATH:/home/python/.local/bin/:$WORKDIR/:/home/gitpod/.local/bin"

RUN pip install --user pylint
RUN pip install --user black

# Install some basic packages (taken from the template repo)
RUN pip install --user --no-cache-dir -r https://raw.githubusercontent.com/runwhen-contrib/codecollection-template/main/requirements.txt

# Commented out if not needed in the dev container
# Install gcloud sdk 
RUN curl -sSL https://sdk.cloud.google.com | bash
ENV PATH "$PATH:/home/gitpod/google-cloud-sdk/bin/"
RUN gcloud components install gke-gcloud-auth-plugin --quiet
RUN chown -R gitpod:gitpod /home/gitpod/.config/gcloud

# Install lnav (https://github.com/tstack/lnav)
ENV LNAV_VERSION 0.11.2
RUN wget https://github.com/tstack/lnav/releases/download/v${LNAV_VERSION}/lnav-${LNAV_VERSION}-x86_64-linux-musl.zip && \
    unzip lnav-${LNAV_VERSION}-x86_64-linux-musl.zip && \
    cd lnav-${LNAV_VERSION} && \
    mkdir -p $HOME/.lnav/formats/installed && \ 
    mv lnav /home/gitpod/.local/bin/


EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
