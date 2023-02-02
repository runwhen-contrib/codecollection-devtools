FROM gitpod/workspace-full

ENV workdir /workspace/codecollection-devtools
ENV python_version 3.9
RUN mkdir -p $workdir
WORKDIR $workdir

# USER root
# # Install and validate kubectl
# # RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# # RUN curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
# # RUN echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# # RUN rm kubectl.sha256
# # RUN chmod +x kubectl
# # RUN mv kubectl /usr/local/bin/

COPY . .
RUN cp -f .gitpod.settings.json .vscode/settings.json
# Setup user to represent developer permissions in container
# ARG USERNAME=python
# ARG USER_UID=1000
# ARG USER_GID=1000
# RUN useradd -rm -d /home/$USERNAME -s /bin/bash -g root -G sudo -u $USER_UID $USERNAME

# Robotframework setup
RUN pyenv install $python_version
RUN pyenv global 3.9
ENV PYTHONPATH "$PYTHONPATH:.:$workdir/rw-public-codecollection/libraries:$workdir/rw-public-codecollection/codebundles:$workdir/codecollection/libraries:$workdir/codecollection/codebundles:$workdir/dev_facade"
# viewable logs
RUN mkdir -p $workdir/robot_logs
# RUN chown -R 1000:0 /robot_logs
# RUN chown 1000:0 $workdir/ro
ENV PATH "$PATH:/home/python/.local/bin/:$workdir/:/home/gitpod/.local/bin"

RUN mv .pylintrc.google ~/.pylintrc

# RUN chown 1000:0 -R $workdir

# USER $USERNAME
RUN pip install --user pylint
RUN pip install --user black
RUN pip install --user --no-cache-dir -r https://raw.githubusercontent.com/runwhen-contrib/codecollection-template/main/requirements.txt

# # Install gcloud sdk 
# # RUN curl -sSL https://sdk.cloud.google.com | bash
# # ENV PATH "$PATH:/home/python/google-cloud-sdk/bin/"
# # RUN gcloud components install gke-gcloud-auth-plugin --quiet

EXPOSE 3000
CMD ["python", "-m", "http.server", "--bind", "0.0.0.0", "--directory", "$workdir/robot_logs/", "3000"]
