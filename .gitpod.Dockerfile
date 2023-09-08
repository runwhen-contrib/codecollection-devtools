FROM gitpod/workspace-full

ENV WORKDIR /workspace/codecollection-devtools
ENV python_version 3.9.1
ENV ROBOT_LOG_DIR /workspace/robot_logs


RUN mkdir -p $WORKDIR
WORKDIR $WORKDIR

USER root
# Install and validate kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
RUN echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
RUN rm kubectl.sha256
RUN chmod +x kubectl
RUN mv kubectl /usr/local/bin/

# Install packages
RUN apt-get update && \
    apt install -y jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/cache/apt

COPY . .

# Robotframework setup
RUN pyenv install $python_version
RUN pyenv global 3.9
ENV PYTHONPATH "$PYTHONPATH:.:$WORKDIR/rw-public-codecollection/libraries:$WORKDIR/rw-public-codecollection/codebundles:$WORKDIR/codecollection/libraries:$WORKDIR/codecollection/codebundles:$WORKDIR/dev_facade"
ENV RW_SVC_URLS '{"kubectl":"https://kubectl.sandbox.runwhen.com","curl":"https://curl.sandbox.runwhen.com","grpcurl":"https://grpcurl.sandbox.runwhen.com","gcloud":"https://gcloud.sandbox.runwhen.com","aws":"https://aws.sandbox.runwhen.com"}'

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

EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
