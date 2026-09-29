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

echo "[1/11] shell syntax"
for file in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  bash -n "$file" || fail "syntax: $file"
done
pass "shell syntax"

echo "[2/11] executable entry point"
[[ -x "$ROOT/ori" ]] || fail "ori is not executable"
grep -Fq 'main "$@"' "$ROOT/ori" || fail "ori does not dispatch main"
pass "entry point"

echo "[3/11] game profiles"
python3 - "$ROOT/config/blind.plist" "$ROOT/config/blind-de.plist" "$ROOT/config/wotw.plist" <<'PY'
import plistlib, sys
expected = [
    ("blind", 261570, "ori.exe"),
    ("blind-de", 387290, "OriDE.exe"),
    ("wotw", 1057090, "oriwotw.exe"),
]
for path, exp in zip(sys.argv[1:], expected):
    with open(path, "rb") as f:
        p = plistlib.load(f)
    slug, appid, exe = exp
    assert p["slug"] == slug
    assert p["steamAppId"] == appid
    assert p["executable"] == exe
    assert p["runtimeVersion"] == "3.1.1"
    if p["slug"] in ("blind", "blind-de"):
        assert p["preferredRenderer"] == "DXVK"
        assert p["preferredRendererVersion"] == "1.10.3"
        assert p["highDpiAware"] == 1
    else:
        assert p["preferredRenderer"] == "DXMT"
        assert p["preferredRendererVersion"] == "0.80"
    assert p["display"]["targetWidth"] == 1920
    assert p["display"]["targetHeight"] == 1080
    if p["slug"] in ("blind", "blind-de"):
        assert p["display"]["retinaMode"] == "y"
        assert p["display"]["dpi"] == 192
    else:
        assert p["display"]["retinaMode"] == "n"
    assert p["display"]["videoMemoryMB"] == 8192
    assert p["environment"]["WINEESYNC"] == "1"
    assert p["environment"]["MONO_THREADS_SUSPEND"] == "1"
    assert p["environment"]["D3DM_FORCE_D3D11"] == "1"
    if p["slug"] in ("blind", "blind-de"):
        assert p["environment"]["WINEMSYNC"] == "1"
        assert p["screenmanagerRegistry"] == 1
        assert p["fullscreenRegistryName"] == "Screenmanager Is Fullscreen mode_h3981298716"
    else:
        assert p["environment"]["WINEMSYNC"] == "0"
        assert p["fullscreenRegistryName"] == "Screenmanager Fullscreen mode_h3630240806"
    assert p["audio"]["driver"] == "coreaudio"
PY
pass "game profiles"

echo "[4/11] runtime pin"
grep -Fq 'RUNTIME_VERSION="3.1.1"' "$ROOT/lib/whisky.sh" || fail "runtime is not pinned"
grep -Fq 'RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"' "$ROOT/lib/whisky.sh" || fail "runtime checksum is not pinned"
pass "runtime pin"

echo "[5/11] multi-game detection contract"
grep -Fq 'manifest_for_appid 261570' "$ROOT/lib/steam.sh" || fail "Blind Forest detection missing"
grep -Fq 'manifest_for_appid 387290' "$ROOT/lib/steam.sh" || fail "Blind Forest DE detection missing"
grep -Fq 'manifest_for_appid 1057090' "$ROOT/lib/steam.sh" || fail "Will of the Wisps detection missing"
grep -Fq 'load_game_profile "blind"' "$ROOT/lib/steam.sh" || fail "Blind Forest profile selection missing"
grep -Fq 'load_game_profile "wotw"' "$ROOT/lib/steam.sh" || fail "WotW profile selection missing"
pass "multi-game detection"

echo "[6/11] forced Unity display arguments"
grep -Fq -- '-force-d3d11' "$ROOT/lib/steam.sh" || fail "D3D11 force missing"
grep -Fq -- '-screen-width' "$ROOT/lib/steam.sh" || fail "screen width arg missing"
grep -Fq -- '-screen-height' "$ROOT/lib/steam.sh" || fail "screen height arg missing"
grep -Fq -- '-screen-fullscreen' "$ROOT/lib/steam.sh" || fail "fullscreen arg missing"
pass "Unity display args"

echo "[7/11] tuning contract"
grep -Fq 'TUNING_SCHEMA_VERSION="10"' "$ROOT/lib/whisky.sh" || fail "tuning schema not bumped"
grep -Fq 'sync_program_dll_overrides()' "$ROOT/lib/whisky.sh" || fail "per-program DLL override sync missing"
grep -Fq 'AppDefaults' "$ROOT/lib/whisky.sh" || fail "Wine AppDefaults override scope missing"
if grep -Fq 'export WINEDLLOVERRIDES' "$ROOT/lib/whisky.sh"; then
  fail "WINEDLLOVERRIDES must not leak into Steam/helper environment"
fi
grep -Fq 'deploy_dxvk()' "$ROOT/lib/whisky.sh" || fail "DXVK deployment missing"
grep -Fq 'HIGHDPIAWARE' "$ROOT/lib/whisky.sh" || fail "high-DPI awareness override missing"
grep -Fq "VideoMemorySize" "$ROOT/lib/whisky.sh" || fail "VRAM reporting override missing"
grep -Fq "MONO_THREADS_SUSPEND" "$ROOT/lib/whisky.sh" || fail "Unity performance environment missing"
grep -Fq "HelBuflen" "$ROOT/lib/whisky.sh" || fail "audio buffer tuning missing"
grep -Fq "RetinaMode" "$ROOT/lib/whisky.sh" || fail "Retina handling missing"
grep -Fq "screenmanagerRegistry" "$ROOT/lib/whisky.sh" || fail "profile-aware registry handling missing"
grep -Fq "screenWidthRegistryName" "$ROOT/lib/whisky.sh" || fail "profile width registry key handling missing"
grep -Fq "fullscreenRegistryName" "$ROOT/lib/whisky.sh" || fail "profile fullscreen registry key handling missing"
pass "tuning contract"

echo "[8/11] path safety"
grep -Fq 'rm -rf "$ORI_PREFIX"' "$ROOT/lib/whisky.sh" || fail "prefix reset is not scoped"
if grep -REn 'rm[[:space:]]+-rf[[:space:]]+(")?(~|\$HOME)(/|["[:space:]]|$)' "$ROOT/lib" "$ROOT/ori"; then
  fail "broad home-directory deletion found"
fi
pass "path safety"

echo "[9/11] one-command README"
grep -Fq './ori' "$ROOT/README.md" || fail "README ./ori missing"
grep -Fq 'auto-detect' "$ROOT/README.md" || fail "README auto-detect missing"
pass "README"

echo "[10/11] Steam CEF GPU isolation"
grep -Fq -- '-cef-disable-gpu' "$ROOT/lib/steam.sh" || fail "Steam CEF GPU disable flag missing"
grep -Fq -- '-cef-disable-gpu-compositing' "$ROOT/lib/steam.sh" || fail "Steam CEF compositing disable flag missing"
pass "Steam CEF GPU isolation"

echo "[11/11] secret/logging safety"
if grep -REni '(steamloginsecure|refresh[_-]?token|access[_-]?token|password|passwd).*(echo|printf)' "$ROOT/lib" "$ROOT/ori"; then
  fail "possible secret logging"
fi
pass "secret/logging safety"

echo "All static and fixture tests passed."
