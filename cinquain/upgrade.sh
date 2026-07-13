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
old_env=$(mktemp "$ROOT_DIR/state/env.rollback.XXXXXX")
cp "$ROOT_DIR/.env" "$old_env"
chmod 600 "$old_env"

rollback() {
    echo "升级失败，正在恢复原镜像配置……" >&2
    mv "$old_env" "$ROOT_DIR/.env"
    compose up -d --remove-orphans || true
}
trap rollback INT TERM HUP

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
