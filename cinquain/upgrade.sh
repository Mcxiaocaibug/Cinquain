#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

if [ ! -f .env ]; then
    echo ".env is missing. Run ./install.sh first."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Required tool not found: docker"
    exit 1
fi

# shellcheck disable=SC1091
. ./.env

if [ "${CINQUAIN_BACKUP_BEFORE_UPGRADE:-1}" = "1" ]; then
    ./backup.sh
fi

if [ "${CINQUAIN_BUILD_LOCALLY:-1}" = "1" ]; then
    docker compose up -d --build
else
    docker compose pull caddy homeserver
    docker compose up -d
fi

./doctor.sh
