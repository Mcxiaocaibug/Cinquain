#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export ROOT_DIR
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/common.sh"

require_config
require_docker
require_tool tar

BACKUP_DIR=${CINQUAIN_BACKUP_DIR:-$ROOT_DIR/backups}
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive_name="${CINQUAIN_STACK_NAME}-v${CINQUAIN_VERSION}-${timestamp}.tar.gz"
archive="$BACKUP_DIR/$archive_name"
# Build under a .partial name so an interrupted run can never leave a truncated
# archive sitting under the final name, where restore.sh would happily accept it
# (a missing checksum sidecar used to mean "skip verification").
partial_name="$archive_name.partial"
partial="$BACKUP_DIR/$partial_name"
rm -f "$partial"

homeserver_volume="${CINQUAIN_STACK_NAME}_homeserver_data"
caddy_data_volume="${CINQUAIN_STACK_NAME}_caddy_data"
caddy_config_volume="${CINQUAIN_STACK_NAME}_caddy_config"
for volume in "$homeserver_volume" "$caddy_data_volume" "$caddy_config_volume"; do
    docker volume inspect "$volume" >/dev/null 2>&1 || die "缺少数据卷 $volume；尚未部署或项目名不匹配。"
done

restart_needed=0
cleanup() {
    rm -f "$partial"
    if [ "$restart_needed" -eq 1 ]; then
        compose start homeserver >/dev/null
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

info "暂停 homeserver 以创建 RocksDB 一致性快照"
compose stop -t 90 homeserver
restart_needed=1

docker run --rm \
    -v "$homeserver_volume:/payload/homeserver:ro" \
    -v "$caddy_data_volume:/payload/caddy_data:ro" \
    -v "$caddy_config_volume:/payload/caddy_config:ro" \
    -v "$ROOT_DIR/.env:/payload/config/.env:ro" \
    -v "$ROOT_DIR/continuwuity.toml:/payload/config/continuwuity.toml:ro" \
    -v "$ROOT_DIR/VERSION:/payload/config/VERSION:ro" \
    -v "$BACKUP_DIR:/backup" \
    docker.io/library/busybox:1.36.1 \
    sh -c "tar czf '/backup/$partial_name' -C /payload homeserver caddy_data caddy_config config"

chmod 600 "$partial"
# Prove the archive is complete and readable before it is allowed to become a
# restore candidate.
tar -tzf "$partial" >/dev/null 2>&1 || die "生成的备份归档无法读取，已丢弃。"
checksum=$(sha256_file "$partial")
printf '%s  %s\n' "$checksum" "$archive_name" > "$partial.sha256"
chmod 600 "$partial.sha256"
mv "$partial.sha256" "$archive.sha256"
mv "$partial" "$archive"

restart_needed=0
compose start homeserver >/dev/null
trap - EXIT INT TERM HUP

retention=${CINQUAIN_BACKUP_RETENTION:-7}
# Sweep archives abandoned by earlier interrupted runs.
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CINQUAIN_STACK_NAME}-v*.tar.gz.partial*" -delete
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${CINQUAIN_STACK_NAME}-v*.tar.gz" -print \
    | sort -r \
    | awk -v keep="$retention" 'NR > keep' \
    | while IFS= read -r old; do rm -f "$old" "$old.sha256"; done

echo "备份完成: $archive"
echo "SHA-256: $checksum"
