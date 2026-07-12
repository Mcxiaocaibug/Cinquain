#!/bin/sh

set -eu

VERSION=0.0.1
REPOSITORY=${CINQUAIN_REPOSITORY:-Mcxiaocaibug/Cinquain}
RELEASE_TAG=${CINQUAIN_RELEASE_TAG:-cinquain-v$VERSION}
INSTALL_ROOT=/opt/cinquain
PANEL_BIND=${CINQUAIN_PANEL_BIND:-127.0.0.1}
PANEL_PORT=${CINQUAIN_PANEL_PORT:-7080}
SOURCE_DIR=${CINQUAIN_SOURCE_DIR:-}

die() { echo "错误: $*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "bootstrap.sh 必须以 root 运行：curl ... | sudo sh"

case "$PANEL_PORT" in
    ''|*[!0-9]*) die "CINQUAIN_PANEL_PORT 必须是数字。" ;;
esac
[ "$PANEL_PORT" -ge 1 ] && [ "$PANEL_PORT" -le 65535 ] || die "面板端口必须处于 1-65535。"
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
if [ -n "$SOURCE_DIR" ]; then
    [ -d "$SOURCE_DIR/cinquain" ] || die "CINQUAIN_SOURCE_DIR 必须指向 Cinquain 仓库根目录。"
    tar -C "$SOURCE_DIR/cinquain" -cf - . | tar -C "$INSTALL_ROOT" -xf -
else
    archive="$tmp_dir/cinquain.tar.gz"
    url="https://github.com/$REPOSITORY/archive/refs/tags/$RELEASE_TAG.tar.gz"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --retry-all-errors "$url" -o "$archive"
    top=$(tar -tzf "$archive" | sed -n '1s#/.*##p')
    [ -n "$top" ] || die "无法识别发布归档。"
    tar -xzf "$archive" -C "$tmp_dir"
    [ -d "$tmp_dir/$top/cinquain" ] || die "发布归档缺少 cinquain 目录。"
    tar -C "$tmp_dir/$top/cinquain" -cf - . | tar -C "$INSTALL_ROOT" -xf -
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

info "Cinquain 网页面板已就绪"
if [ "$PANEL_BIND" = "0.0.0.0" ]; then
    echo "警告: 面板正在公网监听。请通过防火墙限制 $PANEL_PORT/tcp，并在部署后改回 127.0.0.1。"
    echo "打开: http://<服务器IP>:$PANEL_PORT/#token=$panel_token"
else
    echo "在你的电脑上执行: ssh -N -L $PANEL_PORT:127.0.0.1:$PANEL_PORT <root@服务器IP>"
    echo "然后打开: http://127.0.0.1:$PANEL_PORT/#token=$panel_token"
fi
echo "令牌保存在 $panel_env（权限 0600）。"
