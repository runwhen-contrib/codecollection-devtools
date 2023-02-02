FROM gitpod/workspace-full

ENV workdir /workspace/codecollection-devtools
ENV python_version 3.9
ENV robot_log_dir /workspace/robot_logs

RUN mkdir -p $workdir
WORKDIR $workdir

## Commented out if not needed in the dev container
# USER root
## Install and validate kubectl
# RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
# RUN echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# RUN rm kubectl.sha256
# RUN chmod +x kubectl
# RUN mv kubectl /usr/local/bin/


COPY . .

# Robotframework setup
RUN pyenv install $python_version
RUN pyenv global 3.9
ENV PYTHONPATH "$PYTHONPATH:.:$workdir/rw-public-codecollection/libraries:$workdir/rw-public-codecollection/codebundles:$workdir/codecollection/libraries:$workdir/codecollection/codebundles:$workdir/dev_facade"

ENV PATH "$PATH:/home/python/.local/bin/:$workdir/:/home/gitpod/.local/bin"
RUN mv .pylintrc.google ~/.pylintrc

# USER $USERNAME
RUN pip install --user pylint
RUN pip install --user black

# Install some basic packages (taken from the template repo)
RUN pip install --user --no-cache-dir -r https://raw.githubusercontent.com/runwhen-contrib/codecollection-template/main/requirements.txt

## Commented out if not needed in the dev container
## Install gcloud sdk 
# RUN curl -sSL https://sdk.cloud.google.com | bash
# ENV PATH "$PATH:/home/python/google-cloud-sdk/bin/"
# RUN gcloud components install gke-gcloud-auth-plugin --quiet

EXPOSE 3000