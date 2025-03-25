ARG BASE_IMAGE=us-docker.pkg.dev/runwhen-nonprod-shared/public-images/robot-runtime-base-image:latest
FROM ${BASE_IMAGE}

ENV RUNWHEN_HOME=/home/runwhen
ENV ROBOT_LOG_DIR=/robot_logs


USER root
# Set up specific RunWhen Home Dir and Permissions
WORKDIR $RUNWHEN_HOME

# Ensure `runwhen` user has a fixed UID and GID (1000)
RUN usermod -u 1000 runwhen && \
    groupmod -g 1000 runwhen

# Install additional packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt

# Install Terraform
ENV TERRAFORM_VERSION=1.11.2
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip terraform -d /usr/local/bin/ && \
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

#Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Create the Log Output Directory as root, then change ownership to `runwhen`
RUN mkdir -p $ROBOT_LOG_DIR && \
    chown runwhen:0 $ROBOT_LOG_DIR && \
    chmod 775 $ROBOT_LOG_DIR

# Set custom TMPDIR
ENV TMPDIR=/tmp/runwhen
RUN mkdir -p $TMPDIR && \
    chown runwhen:0 $TMPDIR && \
    chmod 775 $TMPDIR

# Set up dev scaffolding
# COPY --chown=runwhen:0 dev_facade dev_facade
COPY --chown=runwhen:0 auth auth
COPY --chown=runwhen:0 .pylintrc.google LICENSE ro requirements.txt .


# Add runwhen user to sudoers with no password prompt
RUN echo "runwhen ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Switch to `runwhen` user
USER runwhen
ENV USER "runwhen"
# Set the PATH to include binaries the `runwhen` user will need
ENV PATH "$PATH:/usr/local/bin:/home/runwhen/.local/bin:$RUNWHEN_HOME"


#Requirements for runrobot.py and the core and User RW libs:
RUN pip install --user --no-cache-dir -r requirements.txt
RUN chmod -R g+w ${RUNWHEN_HOME} && \
    chmod -R 0775 $RUNWHEN_HOME

# Set the pythonpath
ENV PYTHONPATH "$PYTHONPATH:.:$RUNWHEN_HOME/rw-public-codecollection/libraries:$RUNWHEN_HOME/rw-public-codecollection/codebundles:$RUNWHEN_HOME/codecollection/libraries:$RUNWHEN_HOME/codecollection/codebundles:$RUNWHEN_HOME/dev_facade"


EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
