#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

echo "[1/8] shell syntax"
for file in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  bash -n "$file" || fail "syntax: $file"
done
pass "shell syntax"

echo "[2/8] executable entry point"
[[ -x "$ROOT/ori" ]] || fail "ori is not executable"
grep -Fq 'main "$@"' "$ROOT/ori" || fail "ori does not dispatch main"
pass "entry point"

echo "[3/8] profile JSON"
plutil -lint "$ROOT/config/ori.json" >/dev/null || fail "invalid config/ori.json"
app_id="$(plutil -extract steamAppId raw -o - "$ROOT/config/ori.json")"
exe="$(plutil -extract executable raw -o - "$ROOT/config/ori.json")"
renderer="$(plutil -extract preferredRenderer raw -o - "$ROOT/config/ori.json")"
[[ "$app_id" == "1057090" ]] || fail "wrong Steam App ID: $app_id"
[[ "$exe" == "oriwotw.exe" ]] || fail "wrong executable: $exe"
[[ "$renderer" == "DXMT" ]] || fail "wrong preferred renderer: $renderer"
pass "profile"

echo "[4/8] pinned runtime integrity contract"
grep -Fq 'RUNTIME_VERSION="3.1.1"' "$ROOT/lib/whisky.sh" || fail "runtime is not pinned"
grep -Fq 'RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"' "$ROOT/lib/whisky.sh" || fail "runtime checksum is not pinned"
grep -Fq 'sha256_file "$archive"' "$ROOT/lib/whisky.sh" || fail "runtime archive is not hashed"
pass "runtime pin"

echo "[5/8] path safety"
grep -Fq 'rm -rf "$ORI_PREFIX"' "$ROOT/lib/whisky.sh" || fail "prefix reset is not explicitly scoped"
if grep -REn 'rm[[:space:]]+-rf[[:space:]]+(")?(~|\$HOME)(/|["[:space:]]|$)' "$ROOT/lib" "$ROOT/ori"; then
  fail "broad home-directory deletion found"
fi
pass "path safety"

echo "[6/8] Steam manifest parsing fixture"
fixture="$TMP/appmanifest_1057090.acf"
cat > "$fixture" <<'EOF'
"AppState"
{
  "appid" "1057090"
  "name" "Ori and the Will of the Wisps"
  "installdir" "Ori and the Will of the Wisps"
}
EOF
grep -Eq '"appid"[[:space:]]+"1057090"' "$fixture" || fail "manifest fixture not detected"
install_dir="$(awk -F'"' '/"installdir"/ {print $4; exit}' "$fixture")"
[[ "$install_dir" == "Ori and the Will of the Wisps" ]] || fail "install-dir parser"
pass "Steam manifest"

echo "[7/8] one-command README contract"
grep -Fq 'git clone https://github.com/vladddanyliuk/ori-mac-launcher.git' "$ROOT/README.md" || fail "README clone command missing"
grep -Fq './ori' "$ROOT/README.md" || fail "README ./ori command missing"
if grep -Eq 'brew install|open -a Whisky|chmod \+x' "$ROOT/README.md"; then
  fail "README requires extra bootstrap command"
fi
pass "one-command README"

echo "[8/8] secret/logging safety"
if grep -REni '(steamloginsecure|refresh[_-]?token|access[_-]?token|password|passwd).*(echo|printf)' "$ROOT/lib" "$ROOT/ori"; then
  fail "possible secret logging"
fi
pass "secret/logging safety"

echo "All static and fixture tests passed."
