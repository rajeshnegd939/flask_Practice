#!/bin/bash
# EC2 user data for the staging / production servers (Amazon Linux 2023).
# Installs Docker and the Compose plugin. The app is deployed later by the
# pipelines through AWS SSM (deploy/remote-deploy.sh), so no SSH is needed.
set -euxo pipefail
exec > >(tee /var/log/server-setup.log) 2>&1

dnf install -y docker
systemctl enable --now docker

mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

mkdir -p /opt/flask-app/releases /opt/flask-app/shared
