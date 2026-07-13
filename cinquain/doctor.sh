#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
export ROOT_DIR
# shellcheck disable=SC1091
. "$ROOT_DIR/lib/common.sh"

WAIT_SECONDS=0
if [ "${1:-}" = "--wait" ]; then
    WAIT_SECONDS=${2:-180}
fi

require_config
require_docker
require_tool curl

check_once() {
    failures=0
    running=$(compose ps --status running --services 2>/dev/null || true)
    for service in homeserver caddy; do
        if printf '%s\n' "$running" | grep -qx "$service"; then
            printf '%-32s %s\n' "容器 $service" "OK"
        else
            printf '%-32s %s\n' "容器 $service" "FAILED"
            failures=$((failures + 1))
        fi
    done

    base="https://$CINQUAIN_SERVER_NAME"
    check_url() {
        label=$1
        path=$2
        pattern=$3
        printf '%-32s ' "$label"
        if body=$(curl --silent --show-error --fail --max-time 15 "$base$path" 2>/dev/null) && \
            printf '%s' "$body" | grep -q "$pattern"; then
            echo "OK"
        else
            echo "FAILED"
            failures=$((failures + 1))
        fi
    }

    check_url "Matrix Client API" "/_matrix/client/versions" '"versions"'
    check_url "Matrix Federation API" "/_matrix/federation/v1/version" '"server"'
    check_url "Client discovery" "/.well-known/matrix/client" '"m.homeserver"'
    check_url "Server discovery" "/.well-known/matrix/server" '"m.server"'
    check_url "Support discovery" "/.well-known/matrix/support" '"contacts"'
    check_url "Cinquain landing page" "/" 'Cinquain'

    [ "$failures" -eq 0 ]
}

if [ "$WAIT_SECONDS" -gt 0 ]; then
    deadline=$(( $(date +%s) + WAIT_SECONDS ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if check_once; then
            echo "所有生产健康检查已通过。"
            exit 0
        fi
        echo "服务或 TLS 尚未就绪，5 秒后重试……"
        sleep 5
    done
    echo "等待服务就绪超时。请确认 DNS 已指向本机、80/443 端口开放，并运行 ./cinquain logs。" >&2
    exit 1
fi

if check_once; then
    echo "所有生产健康检查已通过。"
else
    echo "健康检查失败。请运行 ./cinquain logs 查看原因。" >&2
    exit 1
fi
