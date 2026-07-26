#!/bin/sh

set -eu
ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$ROOT_DIR/.." && pwd)
failures=0
skipped=0

pass() { printf '%-44s OK\n' "$1"; }
fail() { printf '%-44s FAILED\n' "$1"; failures=$((failures + 1)); }
# Always announce a skip: a silently omitted check makes a green preflight look
# like far more coverage than it actually had.
skip() { printf '%-44s SKIPPED (%s)\n' "$1" "$2"; skipped=$((skipped + 1)); }

for file in \
    VERSION .env.example docker-compose.yml Caddyfile continuwuity-resolv.conf \
    cinquain install.sh bootstrap.sh doctor.sh backup.sh restore.sh upgrade.sh \
    panel/server.py panel/site/index.html panel/site/app.css panel/site/app.js \
    site/index.html site/support/index.html site/assets/app.css; do
    [ -f "$ROOT_DIR/$file" ] || fail "required: $file"
done

for script in cinquain install.sh bootstrap.sh doctor.sh backup.sh restore.sh upgrade.sh preflight.sh lib/common.sh tests/install-smoke.sh; do
    if sh -n "$ROOT_DIR/$script"; then pass "shell syntax: $script"; else fail "shell syntax: $script"; fi
done

if PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT_DIR/tests" -p 'test_*.py'; then
    pass "Python unit/integration tests"
else
    fail "Python unit/integration tests"
fi

if sh "$ROOT_DIR/tests/install-smoke.sh"; then pass "installer smoke test"; else fail "installer smoke test"; fi

if command -v node >/dev/null 2>&1; then
    if node "$ROOT_DIR/tests/panel-ui.mjs"; then pass "panel UI tests"; else fail "panel UI tests"; fi
else
    skip "panel UI tests" "Node unavailable"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if docker compose --project-directory "$ROOT_DIR" --env-file "$ROOT_DIR/.env.example" -f "$ROOT_DIR/docker-compose.yml" config --quiet; then
        pass "Docker Compose model"
    else
        fail "Docker Compose model"
    fi
elif command -v docker-compose >/dev/null 2>&1; then
    if docker-compose --project-directory "$ROOT_DIR" --env-file "$ROOT_DIR/.env.example" -f "$ROOT_DIR/docker-compose.yml" config --quiet; then
        pass "Docker Compose model"
    else
        fail "Docker Compose model"
    fi
else
    skip "Docker Compose model" "Docker unavailable"
fi

if command -v caddy >/dev/null 2>&1; then
    if CINQUAIN_SERVER_NAME=matrix.example.test CINQUAIN_OPERATOR_EMAIL=admin@example.test \
        caddy validate --config "$ROOT_DIR/Caddyfile" >/dev/null 2>&1; then
        pass "Caddy production configuration"
    else
        fail "Caddy production configuration"
    fi
else
    skip "Caddy production configuration" "caddy unavailable"
fi

if grep -R -nE 'CINQUAIN_PANEL_BIND:-0\.0\.0\.0|CINQUAIN_PANEL_TOKEN=[A-Za-z0-9]' "$ROOT_DIR" --exclude=preflight.sh >/dev/null 2>&1; then
    fail "panel secrets and loopback defaults"
else
    pass "panel secrets and loopback defaults"
fi

if grep -R -nE 'image:.*:latest([[:space:]]|$)' "$ROOT_DIR/docker-compose.yml" >/dev/null 2>&1; then
    fail "immutable production image tags"
else
    pass "immutable production image tags"
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ROOT_DIR"/*.sh "$ROOT_DIR/cinquain" "$ROOT_DIR/lib"/*.sh "$ROOT_DIR/tests"/*.sh; then
        pass "ShellCheck"
    else
        fail "ShellCheck"
    fi
else
    skip "ShellCheck" "shellcheck unavailable"
fi

if (cd "$REPO_ROOT" && git diff --check); then pass "git whitespace check"; else fail "git whitespace check"; fi

[ "$failures" -eq 0 ] || { echo "Cinquain preflight: $failures 项失败" >&2; exit 1; }
if [ "$skipped" -gt 0 ]; then
    echo "Cinquain preflight 通过，但有 $skipped 项被跳过（缺少对应工具，本机覆盖率低于 CI）。"
else
    echo "Cinquain preflight 全部通过。"
fi
