ARG BASE_IMAGE=us-docker.pkg.dev/runwhen-nonprod-shared/public-images/robot-runtime-base-image:latest
FROM ${BASE_IMAGE}

USER root
# Set up specific RunWhen Home Dir and Permissions
ENV RUNWHEN_HOME=/home/runwhen
WORKDIR $RUNWHEN_HOME

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