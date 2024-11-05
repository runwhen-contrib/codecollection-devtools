ARG BASE_IMAGE=us-docker.pkg.dev/runwhen-nonprod-shared/public-images/robot-runtime-base-image:latest
FROM ${BASE_IMAGE}

USER root
# Set up specific RunWhen Home Dir and Permissions
ENV RUNWHEN_HOME=/home/runwhen
WORKDIR $RUNWHEN_HOME

# Install Terraform
ENV TERRAFORM_VERSION=1.9.8
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip terraform -d /usr/local/bin/ && \
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

#Install go-task
RUN sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
# RUN wget https://github.com/go-task/task/releases/download/v3.39.2/task_linux_386.tar.gz && \
#     mkdir task_linux_386 && \
#     tar -xvzf task_linux_386.tar.gz -C task_linux_386 && \
#     mv task_linux_386/task /usr/local/bin/task && \
#     rm task_linux_386.tar.gz && \
#     rm -rf task_linux_386
# Set the pythonpath
ENV PYTHONPATH "$PYTHONPATH:.:$WORKDIR/rw-public-codecollection/libraries:$WORKDIR/rw-public-codecollection/codebundles:$WORKDIR/codecollection/libraries:$WORKDIR/codecollection/codebundles:$WORKDIR/dev_facade"

COPY --chown=runwhen:0 . .

# Switch to `runwhen` user
USER runwhen

# Set the PATH to include binaries the `runwhen` user will need
ENV PATH "$PATH:/usr/local/bin:/home/runwhen/.local/bin"

#Requirements for runrobot.py and the core and User RW libs:
RUN pip install --user --no-cache-dir -r https://raw.githubusercontent.com/runwhen-contrib/codecollection-template/main/requirements.txt
RUN chmod -R g+w ${RUNWHEN_HOME} && \
    chmod -R 0775 $RUNWHEN_HOME

EXPOSE 3000
CMD python -m http.server --bind 0.0.0.0 --directory $ROBOT_LOG_DIR 3000