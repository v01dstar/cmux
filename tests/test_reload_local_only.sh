#!/usr/bin/env bash
# Exercise argument/auth gates without building or launching an app.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELOAD="${CMUX_TEST_RELOAD_SCRIPT:-$ROOT_DIR/scripts/reload.sh}"
TMP_DIR="$(mktemp -d)"
TAG="local-only-probe-$$"
LOCK_FILE="$(python3 -c 'import os, sys, tempfile; print(os.path.join(tempfile.gettempdir(), "cmux-reload-tags-%d" % os.getuid(), sys.argv[1] + ".lock"))' "$TAG")"
trap 'rm -rf "$TMP_DIR"; rm -f "$LOCK_FILE"' EXIT
mkdir -p "$TMP_DIR/scripts/ci"
cat > "$TMP_DIR/scripts/ci/resolve-cmux-tui-client-commit.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$CMUX_DEV_BACKEND_MODE" == local && "$CMUX_DEV_CLOUD_ENABLED" == 0 ]] || exit 44
[[ -z "${CMUX_DOGFOOD_STACK_PASSWORD:-}" && -z "${CMUX_UITEST_STACK_PASSWORD:-}" ]] || exit 45
echo local-only-reached-client-resolution >&2
exit 43
EOF
chmod +x "$TMP_DIR/scripts/ci/resolve-cmux-tui-client-commit.sh"
run_reload() {
  set +e
  OUTPUT="$(cd "$TMP_DIR" && env -u CMUX_TUI_CLIENT_LOCAL -u CMUX_TUI_CLIENT_MANIFEST_URL \
    -u CMUX_SKIP_CMUX_TUI_CLIENT -u CMUX_RELOAD_TAG_LOCK_OWNER \
    CMUX_DOGFOOD_STACK_PASSWORD=dummy CMUX_UITEST_STACK_PASSWORD=dummy \
    "$RELOAD" --tag "$TAG" --launch --no-global-cli-links "$@" 2>&1)"
  STATUS=$?
  set -e
}
fail() { echo "FAIL: $*" >&2; exit 1; }
run_reload --local-only
[[ "$STATUS" != 0 && "$OUTPUT" == *local-only-reached-client-resolution* ]] \
  || fail "local mode did not reach the build-input sentinel: $OUTPUT"
echo 'PASS: local mode reaches build preparation without auth credentials'
for option in --prod-auth '--auth-profile personal' '--credentials-file /nonexistent' '--expected-account test@example.com'; do
  # These fixed test cases intentionally expand into flag/value pairs.
  run_reload --local-only $option
  [[ "$STATUS" == 1 && "$OUTPUT" == *'--local-only cannot be combined with'* ]] \
    || fail "conflicting authentication option accepted: $option: $OUTPUT"
done
echo 'PASS: local mode rejects authenticated modes'
run_reload --credentials-file "$TMP_DIR/missing-credentials"
[[ "$STATUS" == 2 && "$OUTPUT" == *'tagged launches require authenticated dev credentials'* ]] \
  || fail "ordinary authenticated launch gate changed: $OUTPUT"
echo 'PASS: ordinary tagged launches still require credentials'
