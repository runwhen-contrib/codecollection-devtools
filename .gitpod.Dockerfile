FROM gitpod/workspace-full
FROM python:3.9.1 as runtime
RUN mkdir -p /app
WORKDIR /app

USER root
# Install and validate kubectl
# RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
# RUN echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# RUN rm kubectl.sha256
# RUN chmod +x kubectl
# RUN mv kubectl /usr/local/bin/

COPY . .

# Setup user to represent developer permissions in container
ARG USERNAME=python
ARG USER_UID=1000
ARG USER_GID=1000
RUN useradd -rm -d /home/$USERNAME -s /bin/bash -g root -G sudo -u $USER_UID $USERNAME

# Robotframework setup
ENV PYTHONPATH "$PYTHONPATH:.:/app/rw-public-codecollection/libraries:/app/rw-public-codecollection/codebundles:/app/codecollection/libraries:/app/codecollection/codebundles:/app/dev_facade"
# viewable logs
RUN mkdir -p /robot_logs
RUN chown -R 1000:0 /robot_logs
RUN chown 1000:0 /app/ro
ENV PATH "$PATH:/home/python/.local/bin/:/app/"

RUN mv .pylintrc.google ~/.pylintrc

RUN chown 1000:0 -R /app

USER $USERNAME
RUN pip install --user pylint
RUN pip install --user black

# Install gcloud sdk 
# RUN curl -sSL https://sdk.cloud.google.com | bash
# ENV PATH "$PATH:/home/python/google-cloud-sdk/bin/"
# RUN gcloud components install gke-gcloud-auth-plugin --quiet

EXPOSE 3000
CMD ["python", "-m", "http.server", "--bind", "0.0.0.0", "--directory", "/robot_logs/", "3000"]
