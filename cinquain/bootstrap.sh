#!/bin/sh

set -eu

VERSION=0.0.2
REPOSITORY=${CINQUAIN_REPOSITORY:-Mcxiaocaibug/Cinquain}
RELEASE_TAG=${CINQUAIN_RELEASE_TAG:-cinquain-v$VERSION}
INSTALL_ROOT=/opt/cinquain
PANEL_BIND=${CINQUAIN_PANEL_BIND:-127.0.0.1}
PANEL_PORT=${CINQUAIN_PANEL_PORT:-7080}
SOURCE_DIR=${CINQUAIN_SOURCE_DIR:-}
EXPECTED_SHA256=${CINQUAIN_SHA256:-}

# Supplying both a domain and an operator email turns bootstrap into a complete
# unattended deployment; without them it only installs the panel and hands the
# operator a one-time URL.
#   curl -fsSL .../bootstrap.sh | sudo sh -s -- matrix.example.com admin@example.com
#   curl -fsSL .../bootstrap.sh | sudo CINQUAIN_DOMAIN=... CINQUAIN_EMAIL=... sh
DOMAIN=${CINQUAIN_DOMAIN:-${1:-}}
EMAIL=${CINQUAIN_EMAIL:-${2:-}}

die() { echo "错误: $*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "bootstrap.sh 必须以 root 运行：curl ... | sudo sh"

if [ -n "$DOMAIN" ] && [ -z "$EMAIL" ]; then
    die "提供域名时必须同时提供管理员邮箱（用于 Let's Encrypt 到期通知）。"
fi
if [ -z "$DOMAIN" ] && [ -n "$EMAIL" ]; then
    die "提供邮箱时必须同时提供 Matrix 域名。"
fi

case "$PANEL_PORT" in
    ''|*[!0-9]*) die "CINQUAIN_PANEL_PORT 必须是数字。" ;;
esac
if [ "$PANEL_PORT" -lt 1 ] || [ "$PANEL_PORT" -gt 65535 ]; then
    die "面板端口必须处于 1-65535。"
fi
case "$PANEL_BIND" in
    127.0.0.1|::1|0.0.0.0) ;;
    *) die "面板监听地址仅支持 127.0.0.1、::1 或 0.0.0.0。" ;;
esac

install_packages() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y ca-certificates curl git openssl python3 tar
        if ! command -v docker >/dev/null 2>&1; then
            if ! apt-get install -y docker.io docker-compose-v2; then
                apt-get install -y docker.io docker-compose-plugin
            fi
        fi
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl git openssl python3 tar docker docker-compose-plugin
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl git openssl python3 tar docker docker-compose-plugin
    else
        die "当前仅自动支持 Debian/Ubuntu 与 Fedora/RHEL 系列；请先安装 Docker Compose v2、Python 3、curl 和 tar。"
    fi
}

info "安装并验证系统依赖"
install_packages
command -v systemctl >/dev/null 2>&1 || die "需要 systemd 托管受保护的部署面板。"
systemctl enable --now docker
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 安装失败。"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    info "开放 Matrix HTTPS 所需防火墙端口"
    ufw allow 80/tcp
    ufw allow 443/tcp
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    info "开放 Matrix HTTPS 所需防火墙端口"
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinquain-bootstrap.XXXXXX")
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

info "安装 Cinquain $VERSION 到 $INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
# `set -e` does not react to a failure in any but the last command of a pipeline,
# and POSIX sh has no pipefail, so stage the copy through a file instead of
# piping tar into tar.
copy_tree() {
    tar -C "$1" -cf "$tmp_dir/payload.tar" .
    tar -C "$2" -xf "$tmp_dir/payload.tar"
    rm -f "$tmp_dir/payload.tar"
}

if [ -n "$SOURCE_DIR" ]; then
    [ -d "$SOURCE_DIR/cinquain" ] || die "CINQUAIN_SOURCE_DIR 必须指向 Cinquain 仓库根目录。"
    copy_tree "$SOURCE_DIR/cinquain" "$INSTALL_ROOT"
else
    fetch() {
        curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --retry-all-errors "$1" -o "$2"
    }
    sha256_of() {
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$1" | awk '{print $1}'
        else
            shasum -a 256 "$1" | awk '{print $1}'
        fi
    }

    archive="$tmp_dir/cinquain.tar.gz"
    release_base="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
    # Prefer the published deployment bundle: the release workflow ships it with a
    # .sha256 sidecar, so `curl | sudo sh` can verify what it is about to install
    # without the operator supplying anything. GitHub's auto-generated source
    # tarball has no checksum and is not byte-stable, so it is only the fallback.
    if fetch "$release_base/cinquain-$VERSION.tar.gz" "$archive" 2>/dev/null; then
        expected=$EXPECTED_SHA256
        if [ -z "$expected" ] && fetch "$release_base/cinquain-$VERSION.tar.gz.sha256" "$archive.sha256" 2>/dev/null; then
            expected=$(awk '{print $1}' "$archive.sha256")
        fi
        if [ -n "$expected" ]; then
            actual=$(sha256_of "$archive")
            [ "$actual" = "$expected" ] \
                || die "发布归档校验和不匹配（期望 $expected，实际 $actual）。"
            info "发布归档校验和匹配"
        else
            echo "警告: 未能获取校验文件，跳过完整性校验。" >&2
        fi
        top=cinquain
    else
        info "未找到发布产物，回退到源码归档"
        fetch "https://github.com/$REPOSITORY/archive/refs/tags/$RELEASE_TAG.tar.gz" "$archive"
        if [ -n "$EXPECTED_SHA256" ]; then
            actual=$(sha256_of "$archive")
            [ "$actual" = "$EXPECTED_SHA256" ] \
                || die "源码归档校验和不匹配（期望 $EXPECTED_SHA256，实际 $actual）。"
            info "源码归档校验和匹配"
        fi
        top=$(tar -tzf "$archive" | sed -n '1s#/.*##p')
        [ -n "$top" ] || die "无法识别发布归档。"
        top="$top/cinquain"
    fi

    tar -xzf "$archive" -C "$tmp_dir"
    [ -d "$tmp_dir/$top" ] || die "归档缺少 cinquain 目录。"
    copy_tree "$tmp_dir/$top" "$INSTALL_ROOT"
fi

find "$INSTALL_ROOT" -type f -name '*.sh' -exec chmod 755 {} \;
chmod 755 "$INSTALL_ROOT/cinquain" "$INSTALL_ROOT/panel/server.py" "$INSTALL_ROOT/lib"/*.py
mkdir -p "$INSTALL_ROOT/state" "$INSTALL_ROOT/backups" /etc/cinquain
chmod 700 "$INSTALL_ROOT/state" "$INSTALL_ROOT/backups" /etc/cinquain

panel_token=$(openssl rand -hex 32)
panel_env=/etc/cinquain/panel.env
umask 077
{
    echo "CINQUAIN_ROOT=$INSTALL_ROOT"
    echo "CINQUAIN_PANEL_BIND=$PANEL_BIND"
    echo "CINQUAIN_PANEL_PORT=$PANEL_PORT"
    echo "CINQUAIN_PANEL_TOKEN=$panel_token"
} > "$panel_env"
chmod 600 "$panel_env"

install -m 0644 "$INSTALL_ROOT/systemd/cinquain-panel.service" /etc/systemd/system/cinquain-panel.service
systemctl daemon-reload
systemctl enable --now cinquain-panel.service

panel_url_hint() {
    if [ "$PANEL_BIND" = "0.0.0.0" ]; then
        echo "警告: 面板正在公网监听。请通过防火墙限制 $PANEL_PORT/tcp，并在部署后改回 127.0.0.1。"
        echo "运维面板: http://<服务器IP>:$PANEL_PORT/#token=$panel_token"
    else
        echo "运维面板: 先在你的电脑上执行"
        echo "          ssh -N -L $PANEL_PORT:127.0.0.1:$PANEL_PORT <root@服务器IP>"
        echo "          再打开 http://127.0.0.1:$PANEL_PORT/#token=$panel_token"
    fi
    echo "令牌保存在 $panel_env（权限 0600）。"
}

if [ -n "$DOMAIN" ]; then
    info "开始全自动部署 $DOMAIN"
    # cinquain deploy validates the domain/email, checks DNS and 80/443, writes the
    # configuration, starts the stack, waits for TLS and prints the first-account
    # token. Any failure aborts here with a specific reason.
    "$INSTALL_ROOT/cinquain" deploy "$DOMAIN" "$EMAIL"
    echo
    info "Cinquain $VERSION 部署完成"
    panel_url_hint
else
    info "Cinquain 网页面板已就绪"
    echo "尚未部署 homeserver。可在面板中完成，或直接执行:"
    echo "  $INSTALL_ROOT/cinquain deploy <Matrix域名> <管理员邮箱>"
    echo
    panel_url_hint
fi
