#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export ROOT_DIR
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/common.sh"

[ "$#" -eq 1 ] || die "用法: ./cinquain restore <backup.tar.gz>"
archive=$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")
[ -f "$archive" ] || die "备份文件不存在: $archive"
require_config
require_docker
require_tool tar

if [ -f "$archive.sha256" ]; then
    expected=$(awk '{print $1}' "$archive.sha256")
    actual=$(sha256_file "$archive")
    [ "$expected" = "$actual" ] || die "备份校验和不匹配，拒绝恢复。"
fi

listing=$(tar -tzf "$archive") || die "无法读取备份归档。"
printf '%s\n' "$listing" | grep -Eq '^homeserver/' || die "归档不含 homeserver 数据。"
if printf '%s\n' "$listing" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    die "归档包含不安全路径，拒绝恢复。"
fi

homeserver_volume="${CINQUAIN_STACK_NAME}_homeserver_data"
caddy_data_volume="${CINQUAIN_STACK_NAME}_caddy_data"
caddy_config_volume="${CINQUAIN_STACK_NAME}_caddy_config"
compose create >/dev/null

info "停止服务并恢复数据卷"
compose down
docker run --rm \
    -v "$homeserver_volume:/restore/homeserver" \
    -v "$caddy_data_volume:/restore/caddy_data" \
    -v "$caddy_config_volume:/restore/caddy_config" \
    -v "$(dirname -- "$archive"):/backup:ro" \
    docker.io/library/busybox:1.36.1 \
    sh -c "find /restore/homeserver /restore/caddy_data /restore/caddy_config -mindepth 1 -delete && tar xzf '/backup/$(basename -- "$archive")' -C /restore"

compose up -d
"$ROOT_DIR/doctor.sh" --wait 180
echo "恢复完成。部署配置保持当前值，归档内配置仅用于审计。"
