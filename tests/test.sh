#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "[1/6] shell syntax"
for f in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  bash -n "$f" || fail "syntax: $f"
done

echo "[2/6] public one-command contract"
grep -q 'main "$@"' "$ROOT/ori" || fail "ori does not dispatch"
grep -q 'ORI_APP_ID="1057090"' "$ROOT/lib/common.sh" || fail "wrong/missing app id"
grep -q './ori' "$ROOT/README.md" || fail "README missing ./ori"

echo "[3/6] no destructive paths outside owned prefix"
if grep -RE 'rm -rf[[:space:]]+["'"']?\$HOME|rm -rf[[:space:]]+~/' "$ROOT"/lib "$ROOT/ori"; then
  fail "broad home-directory deletion found"
fi
grep -q 'rm -rf "$ORI_PREFIX"' "$ROOT/lib/whisky.sh" || fail "reset is not scoped to ORI_PREFIX"

echo "[4/6] Steam manifest detection fixture"
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
[[ "$install_dir" == "Ori and the Will of the Wisps" ]] || fail "installdir parser"

echo "[5/6] profile JSON"
python3 - "$ROOT/config/ori.json" <<'PY'
import json, sys
p=json.load(open(sys.argv[1]))
assert p["steamAppId"] == 1057090
assert p["preferredRenderer"] == "DXMT"
PY

echo "[6/6] unsafe secret logging scan"
if grep -REi '(password|passwd|steamloginsecure|refresh[_-]?token|access[_-]?token).*(echo|printf)' "$ROOT"/lib "$ROOT/ori"; then
  fail "possible secret logging"
fi

echo "All static/fixture tests passed."
