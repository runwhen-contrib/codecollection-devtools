# Codespaces / Dev Containers apply features (docker-in-docker) in a follow-on build
# stage. That installer sources /etc/os-release and only allows known VERSION_CODENAME
# values. Upstream base images may still report "forky" while apt is bookworm.
#
# This thin layer runs *before* features, so dind works even when GHCR :latest has
# not yet picked up the same normalization in the repo root Dockerfile.
ARG DEVTOOLS_IMAGE=ghcr.io/runwhen-contrib/codecollection-devtools:latest
FROM ${DEVTOOLS_IMAGE}

USER root
RUN set -eux; \
    for f in /usr/lib/os-release /etc/os-release; do \
      [ -e "$f" ] || continue; \
      target="$f"; \
      [ -L "$f" ] && target=$(readlink -f "$f"); \
      grep -q '^ID=debian' "$target" || continue; \
      sed -i \
        -e 's/^VERSION_CODENAME=.*/VERSION_CODENAME=bookworm/' \
        -e 's/^VERSION_ID=.*/VERSION_ID="12"/' \
        -e 's/^VERSION=.*/VERSION="12 (bookworm)"/' \
        -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"|' \
        "$target"; \
    done
USER runwhen
