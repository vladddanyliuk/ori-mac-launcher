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

echo "[1/14] shell syntax"
for file in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  bash -n "$file" || fail "syntax: $file"
done
pass "shell syntax"

echo "[2/14] executable entry point"
[[ -x "$ROOT/ori" ]] || fail "ori is not executable"
grep -Fq 'main "$@"' "$ROOT/ori" || fail "ori does not dispatch main"
pass "entry point"

echo "[3/14] profile JSON"
python3 - "$ROOT/config/ori.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
assert p["steamAppId"] == 1057090
assert p["executable"] == "oriwotw.exe"
assert p["preferredRenderer"] == "DXMT"
assert p["runtimeVersion"] == "3.1.1"
assert p["preferredRendererVersion"] == "0.80"
assert p["dllOverrides"] == "dxgi=n,b;d3d10core=n,b;d3d11=n,b;winemetal=b;d3d12="
assert p["environment"]["LC_ALL"] == "en_US.UTF-8"
assert p["environment"]["STEAM_DISABLE_CEF_SANDBOX"] == "1"
assert p["environment"]["WINHTTP_CONNECT_TIMEOUT"] == "90000"
assert p["display"]["retinaMode"] == "n"
assert p["display"]["dpi"] == 96
assert p["display"]["useNativeResolution"] == 0
assert p["display"]["fullscreenMode"] == 0
assert p["display"]["targetWidth"] == 2560
assert p["display"]["targetHeight"] == 1440
assert p["audio"]["driver"] == "coreaudio"
assert p["audio"]["directSoundBuffer"] == 131072
assert p["environment"]["WINEESYNC"] == "1"
assert p["environment"]["WINEMSYNC"] == "0"
assert p["environment"]["MVK_CONFIG_LOG_LEVEL"] == "1"
PY
pass "profile"

echo "[4/14] pinned runtime integrity contract"
grep -Fq 'RUNTIME_VERSION="3.1.1"' "$ROOT/lib/whisky.sh" || fail "runtime is not pinned"
grep -Fq 'RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"' "$ROOT/lib/whisky.sh" || fail "runtime checksum is not pinned"
grep -Fq 'sha256_file "$archive"' "$ROOT/lib/whisky.sh" || fail "runtime archive is not hashed"
pass "runtime pin"

echo "[5/14] path safety"
grep -Fq 'rm -rf "$ORI_PREFIX"' "$ROOT/lib/whisky.sh" || fail "prefix reset is not explicitly scoped"
if grep -REn 'rm[[:space:]]+-rf[[:space:]]+(")?(~|\$HOME)(/|["[:space:]]|$)' "$ROOT/lib" "$ROOT/ori"; then
  fail "broad home-directory deletion found"
fi
pass "path safety"

echo "[6/14] Steam manifest parsing fixture"
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

echo "[7/14] one-command README contract"
grep -Fq 'git clone https://github.com/vladddanyliuk/ori-mac-launcher.git' "$ROOT/README.md" || fail "README clone command missing"
grep -Fq './ori' "$ROOT/README.md" || fail "README ./ori command missing"
if grep -Eq 'brew install|open -a Whisky|chmod \+x' "$ROOT/README.md"; then
  fail "README requires extra bootstrap command"
fi
pass "one-command README"

echo "[8/14] bootstrap idempotence decisions"
(
  APP_SUPPORT_DIR="$TMP/App Support/OriMac"
  STATE_DIR="$APP_SUPPORT_DIR/state"
  DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
  ROOT_DIR="$ROOT"
  mkdir -p "$STATE_DIR" "$DOWNLOAD_DIR"

  info() { :; }
  warn() { :; }
  error() { :; }
  profile_value() { printf '%s\n' "-all"; }

  # shellcheck source=../lib/whisky.sh
  source "$ROOT/lib/whisky.sh"

  install_calls=0
  runtime_is_usable() { return 0; }
  install_runtime_headless() { install_calls=$((install_calls + 1)); }
  ensure_runtime
  [[ "$install_calls" -eq 0 ]] || fail "healthy runtime was reinstalled"

  runtime_is_usable() { return 1; }
  ensure_runtime
  [[ "$install_calls" -eq 1 ]] || fail "missing runtime was not provisioned exactly once"
) || fail "runtime idempotence"
pass "runtime idempotence"

echo "[9/14] prefix schema state"
(
  APP_SUPPORT_DIR="$TMP/Prefix Test/OriMac"
  STATE_DIR="$APP_SUPPORT_DIR/state"
  DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
  ROOT_DIR="$ROOT"
  mkdir -p "$STATE_DIR" "$APP_SUPPORT_DIR/prefix/drive_c/windows/system32"
  touch "$APP_SUPPORT_DIR/prefix/system.reg"

  info() { :; }
  warn() { :; }
  error() { :; }
  profile_value() { printf '%s\n' "-all"; }

  # shellcheck source=../lib/whisky.sh
  source "$ROOT/lib/whisky.sh"
  validate_prefix_schema
  [[ "$(prefix_state_version)" == "$PREFIX_SCHEMA_VERSION" ]] || fail "unversioned prefix was not safely adopted"
) || fail "prefix schema"
pass "prefix schema"

echo "[10/14] path construction with spaces"
(
  APP_SUPPORT_DIR="$TMP/Path With Spaces/OriMac"
  STATE_DIR="$APP_SUPPORT_DIR/state"
  DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
  ROOT_DIR="$ROOT"
  info() { :; }
  warn() { :; }
  error() { :; }
  profile_value() { printf '%s\n' "-all"; }

  # shellcheck source=../lib/whisky.sh
  source "$ROOT/lib/whisky.sh"
  [[ "$ORI_PREFIX" == "$TMP/Path With Spaces/OriMac/prefix" ]] || fail "prefix path lost spaces"
  [[ "$WHISKY_WINE" == "$TMP/Path With Spaces/OriMac/runtime/Libraries/Wine/bin/wine64" ]] || fail "runtime path lost spaces"
) || fail "path construction"
pass "path construction"

echo "[11/14] Steam installer fixture validation"
(
  APP_SUPPORT_DIR="$TMP/Steam Test/OriMac"
  STATE_DIR="$APP_SUPPORT_DIR/state"
  DOWNLOAD_DIR="$APP_SUPPORT_DIR/downloads"
  ORI_PREFIX="$APP_SUPPORT_DIR/prefix"
  ORI_APP_ID="1057090"
  ORI_EXE="oriwotw.exe"
  mkdir -p "$DOWNLOAD_DIR"

  info() { :; }
  warn() { :; }
  error() { :; }

  # shellcheck source=../lib/steam.sh
  source "$ROOT/lib/steam.sh"

  printf 'MZfixture' > "$STEAM_INSTALLER"
  steam_installer_is_sane || fail "MZ installer fixture rejected"

  printf '<html>not an exe</html>' > "$STEAM_INSTALLER"
  if steam_installer_is_sane; then
    fail "non-PE installer fixture accepted"
  fi
) || fail "Steam installer validation"
pass "Steam installer validation"

echo "[12/14] Mac tuning contract"
grep -Fq "apply_game_tuning" "$ROOT/ori" || fail "launcher does not apply game tuning"
grep -Fq "RetinaMode" "$ROOT/lib/whisky.sh" || fail "Retina registry handling missing"
grep -Fq "HelBuflen" "$ROOT/lib/whisky.sh" || fail "audio buffer tuning missing"
grep -Fq "Screenmanager Resolution Use Native_h1405027254" "$ROOT/lib/whisky.sh" || fail "Ori resolution tuning missing"
grep -Fq "Screenmanager Fullscreen mode_h3630240806" "$ROOT/lib/whisky.sh" || fail "Ori fullscreen tuning missing"
grep -Fq "TUNING_SCHEMA_VERSION=\"3\"" "$ROOT/lib/whisky.sh" || fail "tuning schema not bumped"
pass "Mac tuning contract"

echo "[13/14] Steam library detection contract"
grep -Fq 'ori_manifest_path()' "$ROOT/lib/steam.sh" || fail "dynamic Ori manifest detection missing"
grep -Fq 'find "$ORI_PREFIX/drive_c"' "$ROOT/lib/steam.sh" || fail "alternate Steam library search missing"
grep -Fq 'ori_executable_path()' "$ROOT/lib/steam.sh" || fail "Ori executable diagnostics missing"
pass "Steam library detection contract"

echo "[14/14] secret/logging safety"
if grep -REni '(steamloginsecure|refresh[_-]?token|access[_-]?token|password|passwd).*(echo|printf)' "$ROOT/lib" "$ROOT/ori"; then
  fail "possible secret logging"
fi
pass "secret/logging safety"

echo "All static and fixture tests passed."
