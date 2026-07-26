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

warn() {
    echo "警告: $*" >&2
}

# Continuwuity colourises its startup banner unconditionally: yansi is built
# without the `detect-tty` feature, so `Condition::os_support()` is always true
# and ANSI escapes reach the container log even without a TTY. Strip them before
# parsing anything out of `compose logs`.
strip_ansi() {
    sed "s/$(printf '\033')\[[0-9;]*[a-zA-Z]//g"
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

# Print every address a hostname resolves to, one per line. Exits non-zero when
# the name does not resolve. python3 is already a hard requirement, so prefer it
# over getent/dig which are not present on every minimal image.
resolve_host() {
    python3 - "$1" <<'PY' 2>/dev/null
import socket, sys
try:
    infos = socket.getaddrinfo(sys.argv[1], None)
except OSError:
    sys.exit(1)
for address in sorted({info[4][0] for info in infos}):
    print(address)
PY
}

# Print every address configured on this host, one per line.
local_addresses() {
    if command -v ip >/dev/null 2>&1; then
        ip -o addr show 2>/dev/null | awk '{print $4}' | sed 's#/.*##'
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null | awk '/inet6? /{print $2}' | sed 's/^addr://'
    fi
}

# Succeed when a TCP port already has a listener. Returns 1 when it is free and
# 2 when no supported tool is available to tell.
port_listener() {
    port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    else
        return 2
    fi
}
