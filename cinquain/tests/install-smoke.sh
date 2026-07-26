#!/bin/sh

set -eu
SOURCE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cinquain-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
FIXTURE="$TMP/cinquain"
cp -R "$SOURCE" "$FIXTURE"

FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "$CINQUAIN_TEST_DOCKER_LOG"
case " $* " in
  *" info "*) exit 0 ;;
  *" compose version "*) echo "Docker Compose version v2.35.0"; exit 0 ;;
  *" ps --status running --services "*) printf 'homeserver\ncaddy\n'; exit 0 ;;
  # Continuwuity colourises this banner unconditionally (yansi is built without
  # `detect-tty`), so the fixture carries the real ANSI escapes.
  *" logs --no-color homeserver "*)
    printf 'register an account on \033[1;32mmatrix.example.org\033[0m using the registration token \033[1;32mTest_token-123\033[0m . Pick your own username\n'
    printf 'admin: New registration token issued: `Later9999` . Share it with one person\n'
    exit 0 ;;
  *" compose "*) exit 0 ;;
esac
exit 1
EOF
cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
case "$*" in
  *client/versions*) echo '{"versions":["v1.1"]}' ;;
  *federation/v1/version*) echo '{"server":{"name":"continuwuity"}}' ;;
  *well-known/matrix/client*) echo '{"m.homeserver":{"base_url":"https://matrix.example.org"}}' ;;
  *well-known/matrix/server*) echo '{"m.server":"matrix.example.org:443"}' ;;
  *well-known/matrix/support*) echo '{"contacts":[{"email_address":"ops@example.org"}]}' ;;
  *) echo '<title>Cinquain</title>' ;;
esac
EOF
chmod +x "$FAKE_BIN/docker" "$FAKE_BIN/curl"
export CINQUAIN_TEST_DOCKER_LOG="$TMP/docker.log"

# Runs before the happy path so no server-name lock exists yet: an unresolvable
# domain must be rejected by the DNS gate, not by the lock. ACME can never succeed
# for a name that does not resolve, so failing here beats failing after the stack
# is already up. Skipped when the local resolver hijacks the reserved .invalid TLD.
if (cd "$FIXTURE" && sh -c '. ./lib/common.sh; resolve_host cinquain-smoke.invalid') >/dev/null 2>&1; then
    echo "install-smoke: 跳过 DNS 门禁断言（本地解析器劫持了 .invalid）" >&2
else
    if (cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" ./cinquain deploy cinquain-smoke.invalid ops@example.org) \
        > "$TMP/dns.out" 2>&1; then
        echo "deploy accepted a domain that does not resolve" >&2
        exit 1
    fi
    grep -q '无法解析' "$TMP/dns.out"
fi

(cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" CINQUAIN_SKIP_DNS_CHECK=1 \
    ./install.sh "HTTPS://Matrix.Example.ORG:443/path" "ops+matrix@example.org") > "$TMP/install.out"

grep -qx 'CINQUAIN_SERVER_NAME=matrix.example.org' "$FIXTURE/.env"
grep -qx 'CINQUAIN_OPERATOR_EMAIL=ops+matrix@example.org' "$FIXTURE/.env"
grep -q 'server_name = "matrix.example.org"' "$FIXTURE/continuwuity.toml"
grep -q 'compose .* pull$' "$TMP/docker.log"
grep -q 'compose .* up -d --remove-orphans$' "$TMP/docker.log"
# The banner token must win over the later "New registration token issued" line,
# and the surrounding ANSI escapes must not defeat extraction.
grep -q 'Test_token-123' "$TMP/install.out"
token=$(cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" ./cinquain token)
[ "$token" = "Test_token-123" ]

if (cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" CINQUAIN_SKIP_DNS_CHECK=1 \
    ./install.sh localhost ops@example.org) > "$TMP/invalid.out" 2>&1; then
    echo "invalid domain was accepted" >&2
    exit 1
fi

echo "install-smoke: OK"
