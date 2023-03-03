FROM python:3.9.1 as runtime
ENV WORKDIR /app
ENV ROBOT_LOG_DIR /robot_logs
RUN mkdir -p $WORKDIR
WORKDIR $WORKDIR

USER root
# Install and validate kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
RUN echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
RUN rm kubectl.sha256
RUN chmod +x kubectl
RUN mv kubectl /usr/local/bin/

# Setup user to represent developer permissions in container
ARG USERNAME=python
ARG USER_UID=1000
ARG USER_GID=1000
RUN useradd -rm -d /home/$USERNAME -s /bin/bash -g root -G sudo -u $USER_UID $USERNAME

# Robotframework setup
ENV PYTHONPATH "$PYTHONPATH:.:$WORKDIR/rw-public-codecollection/libraries:$WORKDIR/rw-public-codecollection/codebundles:$WORKDIR/codecollection/libraries:$WORKDIR/codecollection/codebundles:$WORKDIR/dev_facade"
# viewable logs
RUN mkdir -p $ROBOT_LOG_DIR
RUN chown -R 1000:0 $ROBOT_LOG_DIR
RUN chown 1000:0 $WORKDIR/ro
ENV PATH "$PATH:/home/python/.local/bin/:$WORKDIR/"

RUN chown 1000:0 -R $WORKDIR

COPY . .

RUN mv .pylintrc.google ~/.pylintrc

USER $USERNAME
RUN pip install --user pylint
RUN pip install --user black

# Install gcloud sdk 
# TODO: fix userspace install and move up in build so it doesnt break cache
RUN curl -sSL https://sdk.cloud.google.com | bash
ENV PATH "$PATH:/home/python/google-cloud-sdk/bin/"
RUN gcloud components install gke-gcloud-auth-plugin --quiet

EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
