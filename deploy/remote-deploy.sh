#!/bin/bash
# Runs ON the staging / production server (sent by Jenkins or GitHub Actions through AWS SSM).
# Usage: remote-deploy.sh <bundle.tar.gz> <version> <environment>
set -euo pipefail

BUNDLE="$1"
VERSION="$2"
ENVIRONMENT="$3"
BASE=/opt/flask-app
RELEASE="$BASE/releases/$VERSION"

echo "Deploying version $VERSION to $ENVIRONMENT"
mkdir -p "$RELEASE" "$BASE/shared"
tar -xzf "$BUNDLE" -C "$RELEASE"

# app.env (SECRET_KEY) comes with the bundle from GitHub Actions secrets;
# if there is none (Jenkins staging deploy) keep the existing one or create it once
if [ -f "$RELEASE/app.env" ]; then
  mv "$RELEASE/app.env" "$BASE/shared/app.env"
elif [ ! -f "$BASE/shared/app.env" ]; then
  echo "SECRET_KEY=$(openssl rand -hex 32)" > "$BASE/shared/app.env"
fi
chmod 600 "$BASE/shared/app.env"

ln -sfn "$RELEASE" "$BASE/current"
cd "$BASE/current"

docker build -t "flask-practice:$VERSION" .
APP_VERSION="$VERSION" docker compose -p flask-app -f deploy/docker-compose.yml up -d --remove-orphans

# keep only the last 5 releases
ls -1dt "$BASE"/releases/* | tail -n +6 | xargs -r rm -rf

# wait until the app answers
for i in $(seq 1 30); do
  if curl -fs http://localhost/health; then
    echo
    echo "Deploy of $VERSION to $ENVIRONMENT OK"
    exit 0
  fi
  sleep 2
done
echo "App did not become healthy"
docker compose -p flask-app -f deploy/docker-compose.yml logs --tail 50 app
exit 1
