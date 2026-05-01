#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

require_tool() {
    tool_name=$1
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        echo "Required tool not found: $tool_name"
        exit 1
    fi
}

read_env_value() {
    var_name=$1
    sed -n "s/^${var_name}=//p" .env | tail -n 1
}

write_env_value() {
    var_name=$1
    var_value=$2
    tmp_file=$(mktemp "$ROOT_DIR/.env.tmp.XXXXXX")

    awk -v key="$var_name" -v value="$var_value" '
        BEGIN { replaced = 0 }
        index($0, key "=") == 1 {
            if (!replaced) {
                print key "=" value
                replaced = 1
            }
            next
        }
        { print }
        END {
            if (!replaced) {
                print key "=" value
            }
        }
    ' .env > "$tmp_file"

    mv "$tmp_file" .env
}

generate_bootstrap_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
    fi
}

ensure_bootstrap_secret() {
    bootstrap_secret=$(read_env_value CINQUAIN_BOOTSTRAP_SECRET || true)

    if [ -n "$bootstrap_secret" ]; then
        return
    fi

    bootstrap_secret=$(generate_bootstrap_secret)
    write_env_value CINQUAIN_BOOTSTRAP_SECRET "$bootstrap_secret"
    echo "Generated CINQUAIN_BOOTSTRAP_SECRET in $ROOT_DIR/.env"
}

if [ ! -f .env ]; then
    cp .env.example .env
    ensure_bootstrap_secret
    echo "Created $ROOT_DIR/.env from .env.example"
    echo "Edit the values in .env, then run ./install.sh again."
    exit 1
fi

ensure_bootstrap_secret

# shellcheck disable=SC1091
. ./.env

require_value() {
    var_name=$1
    eval "value=\${$var_name:-}"

    if [ -z "$value" ]; then
        echo "Missing required value: $var_name"
        exit 1
    fi
}

require_tool docker

require_value CINQUAIN_STACK_NAME
require_value CINQUAIN_SERVER_NAME
require_value CINQUAIN_BOOTSTRAP_SECRET
require_value CINQUAIN_ACME_EMAIL
require_value CINQUAIN_SUPPORT_EMAIL
require_value CINQUAIN_HOMESERVER_IMAGE

if [ "$CINQUAIN_SERVER_NAME" = "matrix.example.com" ]; then
    echo "CINQUAIN_SERVER_NAME still uses the example value."
    exit 1
fi

echo "Deploying Cinquain for $CINQUAIN_SERVER_NAME"
if [ "${CINQUAIN_BUILD_LOCALLY:-1}" = "1" ]; then
    docker compose up -d --build
else
    docker compose pull caddy homeserver
    docker compose up -d
fi

cat <<EOF

Cinquain is starting.

Next steps:
  1. Open https://$CINQUAIN_SERVER_NAME/
  2. Open https://$CINQUAIN_SERVER_NAME/bootstrap
  3. Use CINQUAIN_BOOTSTRAP_SECRET from .env to create the first administrator
  4. Open https://$CINQUAIN_SERVER_NAME/support
  5. Run ./doctor.sh once TLS is ready
  6. Use ./backup.sh before major upgrades

EOF
