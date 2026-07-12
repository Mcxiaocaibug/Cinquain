#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ "$(basename "$ROOT_DIR")" = "lib" ]; then
    ROOT_DIR=$(CDPATH='' cd -- "$ROOT_DIR/.." && pwd)
fi
export ROOT_DIR

die() {
    echo "错误: $*" >&2
    exit 1
}

info() {
    printf '\n==> %s\n' "$*"
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "缺少必需命令: $1"
}

require_docker() {
    require_tool docker
    docker info >/dev/null 2>&1 || die "Docker daemon 不可用；请启动 Docker 或使用 sudo。"
    docker compose version >/dev/null 2>&1 || die "需要 Docker Compose v2 插件。"
}

require_config() {
    [ -f "$ROOT_DIR/.env" ] || die "尚未配置。请运行 ./install.sh <Matrix域名> <管理员邮箱> 或启动网页面板。"
    [ -f "$ROOT_DIR/continuwuity.toml" ] || die "缺少 continuwuity.toml，请重新运行配置。"
    # shellcheck disable=SC1091
    . "$ROOT_DIR/.env"
}

compose() {
    docker compose --project-directory "$ROOT_DIR" --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/docker-compose.yml" "$@"
}

env_value() {
    key=$1
    sed -n "s/^${key}=//p" "$ROOT_DIR/.env" | tail -n 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}
