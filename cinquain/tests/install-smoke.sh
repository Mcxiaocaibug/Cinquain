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
  *" logs --no-color homeserver "*) echo 'register an account using the registration token Test_token-123 .'; exit 0 ;;
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

(cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" ./install.sh "HTTPS://Matrix.Example.ORG:443/path" "ops+matrix@example.org") > "$TMP/install.out"

grep -qx 'CINQUAIN_SERVER_NAME=matrix.example.org' "$FIXTURE/.env"
grep -qx 'CINQUAIN_OPERATOR_EMAIL=ops+matrix@example.org' "$FIXTURE/.env"
grep -q 'server_name = "matrix.example.org"' "$FIXTURE/continuwuity.toml"
grep -q 'compose .* pull$' "$TMP/docker.log"
grep -q 'compose .* up -d --remove-orphans$' "$TMP/docker.log"
token=$(cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" ./cinquain token)
[ "$token" = "Test_token-123" ]

if (cd "$FIXTURE" && PATH="$FAKE_BIN:$PATH" ./install.sh localhost ops@example.org) > "$TMP/invalid.out" 2>&1; then
    echo "invalid domain was accepted" >&2
    exit 1
fi

echo "install-smoke: OK"
