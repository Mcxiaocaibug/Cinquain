#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export ROOT_DIR
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/common.sh"

require_config
require_docker
new_image=${1:-}
mkdir -p "$ROOT_DIR/state"
chmod 700 "$ROOT_DIR/state"
# Discard snapshots left behind by earlier interrupted upgrades.
find "$ROOT_DIR/state" -maxdepth 1 -type f -name 'env.rollback.*' -delete
old_env=$(mktemp "$ROOT_DIR/state/env.rollback.XXXXXX")
cp "$ROOT_DIR/.env" "$old_env"
chmod 600 "$old_env"

# Must stay idempotent: it is reachable both from the signal trap and from the
# explicit failure branch below, and a second `mv` of an already-moved file would
# abort the handler under `set -e` before the stack was brought back up.
rollback() {
    echo "升级失败，正在恢复原镜像配置……" >&2
    if [ -f "$old_env" ]; then
        mv "$old_env" "$ROOT_DIR/.env"
    fi
    compose up -d --remove-orphans || true
    echo "配置已回滚。数据未被改动；如需回到升级前的数据请执行 ./cinquain restore <备份归档>。" >&2
}
trap 'rollback; exit 130' INT TERM HUP

info "升级前自动备份"
"$ROOT_DIR/backup.sh"

if [ -n "$new_image" ]; then
    python3 "$ROOT_DIR/lib/update_image.py" "$new_image"
    # shellcheck disable=SC1091
    . "$ROOT_DIR/.env"
fi

info "拉取并部署新镜像"
if ! compose pull || ! compose up -d --remove-orphans || ! "$ROOT_DIR/doctor.sh" --wait 180; then
    rollback
    trap - INT TERM HUP
    exit 1
fi

rm -f "$old_env"
trap - INT TERM HUP
echo "升级成功。当前 homeserver 镜像: $CINQUAIN_HOMESERVER_IMAGE"
