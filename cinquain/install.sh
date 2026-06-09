#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

REQUESTED_SERVER_NAME=${CINQUAIN_SERVER_NAME:-}
REQUESTED_OPERATOR_EMAIL=${CINQUAIN_OPERATOR_EMAIL:-${CINQUAIN_ACME_EMAIL:-${CINQUAIN_SUPPORT_EMAIL:-}}}
REQUESTED_BUILD_LOCALLY=${CINQUAIN_BUILD_LOCALLY:-}
REQUESTED_HOMESERVER_IMAGE=${CINQUAIN_HOMESERVER_IMAGE:-}
REQUESTED_HTTP_PORT=${CINQUAIN_HTTP_PORT:-}
REQUESTED_HTTPS_PORT=${CINQUAIN_HTTPS_PORT:-}

usage() {
    cat <<EOF
Usage:
  ./install.sh [matrix-domain] [operator-email]

Examples:
  ./install.sh matrix.example.com admin@example.com
  CINQUAIN_BUILD_LOCALLY=1 ./install.sh matrix.example.com admin@example.com

The installer creates .env on first run, generates the bootstrap secret, then
starts the complete Docker Compose stack: Caddy, TLS, Matrix discovery, and the
homeserver database volume.
EOF
}

require_tool() {
    tool_name=$1
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        echo "Required tool not found: $tool_name"
        exit 1
    fi
}

require_docker_compose() {
    require_tool docker
    if ! docker compose version >/dev/null 2>&1; then
        echo "Docker is installed, but the Compose v2 plugin is not available."
        echo "Install Docker Compose v2, then run ./install.sh again."
        exit 1
    fi
}

read_env_value() {
    var_name=$1
    if [ ! -f .env ]; then
        return 0
    fi

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

normalise_domain() {
    printf "%s" "$1" \
        | sed -e 's#^https\?://##' -e 's#/.*$##' -e 's/[[:space:]]//g'
}

is_example_value() {
    case "$1" in
        "" | "matrix.example.com" | "admin@example.com" | "example.com")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

prompt_value() {
    label=$1
    default_value=${2:-}

    if [ ! -t 0 ]; then
        return 1
    fi

    if [ -n "$default_value" ]; then
        printf "%s [%s]: " "$label" "$default_value" >&2
    else
        printf "%s: " "$label" >&2
    fi

    read -r value
    if [ -z "$value" ]; then
        value=$default_value
    fi

    printf "%s" "$value"
}

ensure_env_file() {
    if [ -f .env ]; then
        return
    fi

    cp .env.example .env
    echo "Created $ROOT_DIR/.env from .env.example"
}

configure_first_run_values() {
    cli_server_name=${1:-}
    cli_operator_email=${2:-}

    if [ -n "$cli_server_name" ]; then
        REQUESTED_SERVER_NAME=$cli_server_name
    fi

    if [ -n "$cli_operator_email" ]; then
        REQUESTED_OPERATOR_EMAIL=$cli_operator_email
    fi

    # shellcheck disable=SC1091
    . ./.env

    current_server_name=${CINQUAIN_SERVER_NAME:-}
    current_acme_email=${CINQUAIN_ACME_EMAIL:-}
    current_support_email=${CINQUAIN_SUPPORT_EMAIL:-}

    if [ -n "$REQUESTED_BUILD_LOCALLY" ]; then
        write_env_value CINQUAIN_BUILD_LOCALLY "$REQUESTED_BUILD_LOCALLY"
    fi

    if [ -n "$REQUESTED_HOMESERVER_IMAGE" ]; then
        write_env_value CINQUAIN_HOMESERVER_IMAGE "$REQUESTED_HOMESERVER_IMAGE"
    fi

    if [ -n "$REQUESTED_HTTP_PORT" ]; then
        write_env_value CINQUAIN_HTTP_PORT "$REQUESTED_HTTP_PORT"
    fi

    if [ -n "$REQUESTED_HTTPS_PORT" ]; then
        write_env_value CINQUAIN_HTTPS_PORT "$REQUESTED_HTTPS_PORT"
    fi

    if [ -n "$REQUESTED_SERVER_NAME" ]; then
        write_env_value CINQUAIN_SERVER_NAME "$(normalise_domain "$REQUESTED_SERVER_NAME")"
    elif is_example_value "$current_server_name"; then
        if value=$(prompt_value "Matrix domain" "$current_server_name"); then
            write_env_value CINQUAIN_SERVER_NAME "$(normalise_domain "$value")"
        else
            usage
            echo
            echo "Missing Matrix domain. Run: ./install.sh matrix.example.com admin@example.com"
            exit 1
        fi
    fi

    if [ -n "$REQUESTED_OPERATOR_EMAIL" ]; then
        write_env_value CINQUAIN_ACME_EMAIL "$REQUESTED_OPERATOR_EMAIL"
        write_env_value CINQUAIN_SUPPORT_EMAIL "$REQUESTED_OPERATOR_EMAIL"
    else
        if is_example_value "$current_acme_email"; then
            if value=$(prompt_value "Operator email" "$current_acme_email"); then
                write_env_value CINQUAIN_ACME_EMAIL "$value"
                if is_example_value "$current_support_email"; then
                    write_env_value CINQUAIN_SUPPORT_EMAIL "$value"
                fi
            else
                usage
                echo
                echo "Missing operator email. Run: ./install.sh matrix.example.com admin@example.com"
                exit 1
            fi
        elif is_example_value "$current_support_email"; then
            write_env_value CINQUAIN_SUPPORT_EMAIL "$current_acme_email"
        fi
    fi
}

if [ ! -f .env ]; then
    ensure_env_file
fi

configure_first_run_values "${1:-}" "${2:-}"
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

require_value CINQUAIN_STACK_NAME
require_value CINQUAIN_SERVER_NAME
require_value CINQUAIN_BOOTSTRAP_SECRET
require_value CINQUAIN_ACME_EMAIL
require_value CINQUAIN_SUPPORT_EMAIL
require_value CINQUAIN_HOMESERVER_IMAGE

if is_example_value "$CINQUAIN_SERVER_NAME"; then
    echo "CINQUAIN_SERVER_NAME still uses the example value."
    exit 1
fi

if is_example_value "$CINQUAIN_ACME_EMAIL"; then
    echo "CINQUAIN_ACME_EMAIL still uses the example value."
    exit 1
fi

require_docker_compose

echo "Deploying Cinquain for $CINQUAIN_SERVER_NAME"
if [ "${CINQUAIN_BUILD_LOCALLY:-0}" = "1" ]; then
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
