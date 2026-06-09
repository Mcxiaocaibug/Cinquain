#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$ROOT_DIR/.." && pwd)
cd "$ROOT_DIR"

failures=0

check_file() {
    path=$1
    if [ ! -f "$path" ]; then
        echo "Missing required file: $path"
        failures=$((failures + 1))
    fi
}

check_shell() {
    path=$1
    if sh -n "$path"; then
        echo "shell: $path OK"
    else
        failures=$((failures + 1))
    fi
}

for path in \
    .env.example \
    Caddyfile \
    docker-compose.yml \
    site/index.html \
    site/deploy/index.html \
    site/support/index.html \
    site/assets/app.css \
    site/assets/app.js \
    tests/deploy-console.mjs \
    tests/install-smoke.sh
do
    check_file "$path"
done

for path in \
    install.sh \
    upgrade.sh \
    backup.sh \
    doctor.sh \
    release-image.sh \
    preflight.sh \
    tests/install-smoke.sh
do
    check_shell "$path"
done

if command -v node >/dev/null 2>&1; then
    if node tests/deploy-console.mjs; then
        :
    else
        failures=$((failures + 1))
    fi
else
    echo "deploy-console: skipped because Node.js is unavailable"
fi

if sh tests/install-smoke.sh; then
    :
else
    failures=$((failures + 1))
fi

if ! grep -q "data-deploy-form" site/deploy/index.html; then
    echo "Deploy console is missing the guided form."
    failures=$((failures + 1))
fi

if ! grep -q "data-copy-target" site/deploy/index.html; then
    echo "Deploy console is missing copy controls."
    failures=$((failures + 1))
fi

if ! grep -q "CINQUAIN_BOOTSTRAP_SECRET=" .env.example; then
    echo ".env.example is missing CINQUAIN_BOOTSTRAP_SECRET."
    failures=$((failures + 1))
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    tmp_env=$(mktemp "$ROOT_DIR/.env.preflight.XXXXXX")
    cp .env.example "$tmp_env"
    sed -i.bak \
        -e "s/^CINQUAIN_SERVER_NAME=.*/CINQUAIN_SERVER_NAME=matrix.example.test/" \
        -e "s/^CINQUAIN_ACME_EMAIL=.*/CINQUAIN_ACME_EMAIL=admin@example.test/" \
        -e "s/^CINQUAIN_SUPPORT_EMAIL=.*/CINQUAIN_SUPPORT_EMAIL=admin@example.test/" \
        "$tmp_env"

    if docker compose --env-file "$tmp_env" config >/dev/null; then
        echo "compose: config OK"
    else
        failures=$((failures + 1))
    fi

    rm -f "$tmp_env" "$tmp_env.bak"
else
    echo "compose: skipped because Docker Compose v2 is unavailable"
fi

if [ "${CINQUAIN_PREFLIGHT_CARGO:-0}" = "1" ]; then
    cd "$REPO_ROOT"
    cargo check --locked -p conduwuit
fi

if [ "$failures" -gt 0 ]; then
    echo
    echo "Cinquain preflight found $failures failure(s)."
    exit 1
fi

echo
echo "Cinquain preflight passed."
