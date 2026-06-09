#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cinquain-install.XXXXXX")

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

fail() {
    echo "install-smoke: $1"
    exit 1
}

make_fixture() {
    fixture=$1
    mkdir -p "$fixture"
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/install.sh" "$fixture/"
}

make_fake_docker() {
    bin_dir=$1
    mkdir -p "$bin_dir"

    cat > "$bin_dir/docker" <<'EOF'
#!/bin/sh
printf "%s\n" "$*" >> "$CINQUAIN_DOCKER_LOG"

if [ "$1" = "compose" ] && [ "${2:-}" = "version" ]; then
    exit 0
fi

if [ "$1" = "compose" ]; then
    exit 0
fi

echo "unexpected docker call: $*" >&2
exit 1
EOF

    chmod +x "$bin_dir/docker"
}

assert_env_line() {
    env_file=$1
    expected=$2

    if ! grep -q "^$expected$" "$env_file"; then
        echo "Expected .env line not found: $expected"
        echo "Current .env:"
        sed -n '1,120p' "$env_file"
        exit 1
    fi
}

FAKE_BIN="$TMP_ROOT/bin"
make_fake_docker "$FAKE_BIN"

PULL_FIXTURE="$TMP_ROOT/pull/cinquain"
make_fixture "$PULL_FIXTURE"
PULL_LOG="$TMP_ROOT/pull-docker.log"
PULL_OUT="$TMP_ROOT/pull.out"

(
    cd "$PULL_FIXTURE"
    PATH="$FAKE_BIN:$PATH" CINQUAIN_DOCKER_LOG="$PULL_LOG" ./install.sh \
        "HTTPS://Matrix.Test.Example:443/path" \
        "ops+test@example.org"
) > "$PULL_OUT"

assert_env_line "$PULL_FIXTURE/.env" "CINQUAIN_SERVER_NAME=matrix.test.example"
assert_env_line "$PULL_FIXTURE/.env" "CINQUAIN_ACME_EMAIL=ops+test@example.org"
assert_env_line "$PULL_FIXTURE/.env" "CINQUAIN_SUPPORT_EMAIL=ops+test@example.org"
grep -Eq '^CINQUAIN_BOOTSTRAP_SECRET=[A-Za-z0-9]{48}$' "$PULL_FIXTURE/.env" \
    || fail "bootstrap secret was not generated"
grep -q '^compose pull caddy homeserver$' "$PULL_LOG" \
    || fail "prebuilt install did not pull images"
grep -q '^compose up -d$' "$PULL_LOG" \
    || fail "prebuilt install did not start compose"

BUILD_FIXTURE="$TMP_ROOT/build/cinquain"
make_fixture "$BUILD_FIXTURE"
BUILD_LOG="$TMP_ROOT/build-docker.log"
BUILD_OUT="$TMP_ROOT/build.out"

(
    cd "$BUILD_FIXTURE"
    PATH="$FAKE_BIN:$PATH" \
        CINQUAIN_DOCKER_LOG="$BUILD_LOG" \
        CINQUAIN_BUILD_LOCALLY=1 \
        CINQUAIN_HOMESERVER_IMAGE=ghcr.io/example/cinquain:dev \
        ./install.sh matrix.build.example ops@example.org
) > "$BUILD_OUT"

assert_env_line "$BUILD_FIXTURE/.env" "CINQUAIN_BUILD_LOCALLY=1"
assert_env_line "$BUILD_FIXTURE/.env" "CINQUAIN_HOMESERVER_IMAGE=ghcr.io/example/cinquain:dev"
grep -q '^compose up -d --build$' "$BUILD_LOG" \
    || fail "local build install did not run compose build"

INVALID_FIXTURE="$TMP_ROOT/invalid/cinquain"
make_fixture "$INVALID_FIXTURE"
INVALID_LOG="$TMP_ROOT/invalid-docker.log"
INVALID_OUT="$TMP_ROOT/invalid.out"

if (
    cd "$INVALID_FIXTURE"
    PATH="$FAKE_BIN:$PATH" CINQUAIN_DOCKER_LOG="$INVALID_LOG" ./install.sh \
        "not-a-domain" \
        "ops@example.org"
) > "$INVALID_OUT" 2>&1; then
    fail "invalid domain was accepted"
fi

grep -q 'CINQUAIN_SERVER_NAME is not a valid DNS name.' "$INVALID_OUT" \
    || fail "invalid domain error message was not shown"

echo "install-smoke: OK"
