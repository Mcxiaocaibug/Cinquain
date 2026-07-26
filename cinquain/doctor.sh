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

https_port=${CINQUAIN_HTTPS_PORT:-443}
if [ "$https_port" = "443" ]; then
    base="https://$CINQUAIN_SERVER_NAME"
else
    base="https://$CINQUAIN_SERVER_NAME:$https_port"
fi

check_once() {
    failures=0
    loopback=0
    running=$(compose ps --status running --services 2>/dev/null || true)
    for service in homeserver caddy; do
        if printf '%s\n' "$running" | grep -qx "$service"; then
            printf '%-32s %s\n' "容器 $service" "OK"
        else
            printf '%-32s %s\n' "容器 $service" "FAILED"
            failures=$((failures + 1))
        fi
    done

    check_url() {
        label=$1
        path=$2
        pattern=$3
        printf '%-32s ' "$label"
        if body=$(curl --silent --show-error --fail --max-time 15 "$base$path" 2>/dev/null) && \
            printf '%s' "$body" | grep -q "$pattern"; then
            echo "OK"
            return 0
        fi
        # Plenty of hosts cannot reach their own public address because the
        # network provides no NAT hairpin. Retry against the local Caddy using the
        # real SNI so the certificate still verifies; that proves the stack serves
        # correctly even when the round trip through the internet is untestable
        # from here.
        if body=$(curl --silent --show-error --fail --max-time 15 \
            --resolve "$CINQUAIN_SERVER_NAME:$https_port:127.0.0.1" "$base$path" 2>/dev/null) && \
            printf '%s' "$body" | grep -q "$pattern"; then
            echo "OK (本机回环)"
            loopback=$((loopback + 1))
            return 0
        fi
        echo "FAILED"
        failures=$((failures + 1))
    }

    check_url "Matrix Client API" "/_matrix/client/versions" '"versions"'
    check_url "Matrix Federation API" "/_matrix/federation/v1/version" '"server"'
    check_url "Client discovery" "/.well-known/matrix/client" '"m.homeserver"'
    check_url "Server discovery" "/.well-known/matrix/server" '"m.server"'
    check_url "Support discovery" "/.well-known/matrix/support" '"contacts"'
    check_url "Cinquain landing page" "/" 'Cinquain'

    if [ "$failures" -eq 0 ] && [ "$loopback" -gt 0 ]; then
        warn "部分检查仅通过本机回环成功。本机无法访问自己的公网地址（缺少 NAT hairpin）时属正常现象，"
        warn "但请从另一个网络确认 https://$CINQUAIN_SERVER_NAME 可访问，否则联邦通信会失败。"
    fi

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
