ARG BASE_IMAGE=us-docker.pkg.dev/runwhen-nonprod-shared/public-images/robot-runtime-base-image:latest
FROM ${BASE_IMAGE}

ENV ROBOT_LOG_DIR /robot_logs
ENV RUNWHEN_HOME=/home/runwhen


USER root
# Set up specific RunWhen Home Dir and Permissions
WORKDIR $RUNWHEN_HOME

# Install additional packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt

# Install Terraform
ENV TERRAFORM_VERSION=1.9.8
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip terraform -d /usr/local/bin/ && \
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

#Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Set Log Output Dir
RUN mkdir -p $ROBOT_LOG_DIR
RUN chown -R runwhen:0 $ROBOT_LOG_DIR

# Set up dev scaffolding
COPY --chown=runwhen:0 dev_facade dev_facade
COPY --chown=runwhen:0 auth auth
COPY --chown=runwhen:0 .pylintrc.google LICENSE ro .


# Add runwhen user to sudoers with no password prompt
RUN echo "runwhen ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Switch to `runwhen` user
USER runwhen

# Set the PATH to include binaries the `runwhen` user will need
ENV PATH "$PATH:/usr/local/bin:/home/runwhen/.local/bin:$RUNWHEN_HOME"

#Requirements for runrobot.py and the core and User RW libs:
RUN pip install --user --no-cache-dir -r https://raw.githubusercontent.com/runwhen-contrib/codecollection-template/main/requirements.txt
RUN chmod -R g+w ${RUNWHEN_HOME} && \
    chmod -R 0775 $RUNWHEN_HOME

# Set the pythonpath
ENV PYTHONPATH "$PYTHONPATH:.:$RUNWHEN_HOME/rw-public-codecollection/libraries:$RUNWHEN_HOME/rw-public-codecollection/codebundles:$RUNWHEN_HOME/codecollection/libraries:$RUNWHEN_HOME/codecollection/codebundles:$RUNWHEN_HOME/dev_facade"


EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000
