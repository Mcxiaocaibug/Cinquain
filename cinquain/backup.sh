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

for value_name in CINQUAIN_STACK_NAME CINQUAIN_SERVER_NAME; do
    eval "value=\${$value_name:-}"
    if [ -z "$value" ]; then
        echo "Missing required value: $value_name"
        exit 1
    fi
done

BACKUP_DIR="$ROOT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
ARCHIVE_PATH="$BACKUP_DIR/${CINQUAIN_STACK_NAME}-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

DB_VOLUME="${CINQUAIN_STACK_NAME}_db"
CADDY_DATA_VOLUME="${CINQUAIN_STACK_NAME}_caddy_data"

docker run --rm \
    -v "$DB_VOLUME:/db:ro" \
    -v "$CADDY_DATA_VOLUME:/caddy:ro" \
    -v "$BACKUP_DIR:/backup" \
    busybox sh -c "tar czf /backup/$(basename "$ARCHIVE_PATH") -C / db caddy"

echo "Created backup: $ARCHIVE_PATH"
