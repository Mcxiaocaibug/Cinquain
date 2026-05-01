#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

if [ ! -f .env ]; then
    echo ".env is missing. Run ./install.sh first."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Required tool not found: curl"
    exit 1
fi

# shellcheck disable=SC1091
. ./.env

BASE_URL="https://$CINQUAIN_SERVER_NAME"

check() {
    name=$1
    url=$2
    pattern=${3:-}

    printf "%-28s" "$name"

    if body=$(curl --silent --show-error --fail --location "$url"); then
        if [ -n "$pattern" ] && ! printf "%s" "$body" | grep -q "$pattern"; then
            echo "FAILED"
            echo "  Pattern not found: $pattern"
            return 1
        fi

        echo "OK"
        return 0
    fi

    echo "FAILED"
    return 1
}

failures=0

check "Landing page" "$BASE_URL/" "Cinquain" || failures=$((failures + 1))
check "Support page" "$BASE_URL/support" "Operator checklist" || failures=$((failures + 1))
check "Bootstrap page" "$BASE_URL/bootstrap" "Bootstrap" || failures=$((failures + 1))
check "Well-known client" "$BASE_URL/.well-known/matrix/client" "\"m.homeserver\"" || failures=$((failures + 1))
check "Well-known server" "$BASE_URL/.well-known/matrix/server" "\"m.server\"" || failures=$((failures + 1))
check "Client versions" "$BASE_URL/_matrix/client/versions" "\"versions\"" || failures=$((failures + 1))

if [ "$failures" -gt 0 ]; then
    echo
    echo "Doctor found $failures failing checks."
    exit 1
fi

echo
echo "All Cinquain checks passed."
