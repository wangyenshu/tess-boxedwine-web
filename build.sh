#!/usr/bin/env bash
# Build Tess (Pedagoguery Software's symmetry-drawing program) for the browser on Boxedwine.
#
# Uses the official Boxedwine web release (boxedwine.js / boxedwine.wasm and its stripped
# Wine 11 file system) and the Windows Tess installer, unpacked with 7-Zip. No compiler
# is needed: Tess has no sound and only light graphics, so the release binaries are
# enough (elona-boxedwine-web compiles Boxedwine itself to fix an audio crash and to
# grow the heap, neither of which Tess needs).
#
# Tess's 3D views (cone, cylinder, torus) use OpenGL, which Boxedwine's web build lacks:
# without it, picking one crashes the emulator. Mesa's software OpenGL for Windows
# (the x86 opengl32.dll from pal1000/mesa-dist-win) goes next to tess.exe and renders
# them on the CPU inside the emulator.
#
#   ./build.sh            -> dist/ (serve it over http(s))
#
# Options (environment variables):
#   BOXEDWINE_VERSION=26R1    Boxedwine release (tag <version>.0)
#   BUILD=MultiThreaded       MultiThreaded (faster; needs cross-origin isolation, which
#                             coi-serviceworker.js provides) or SingleThreaded (runs on
#                             any static host, no service worker)
#   TESS_URL=...              where to download tess_setup.exe
#   TESS_SETUP=/path/tess_setup.exe   use a local installer instead of downloading
#   MESA=1                    0 leaves Mesa out (~9 MB smaller; the 3D views then crash)
#   MESA_VERSION=20.1.8       mesa-dist-win release; the last with one self-contained
#                             x86 opengl32.dll (21.3+ split the driver out)
#
# Needs: bash, curl, unzip, zip, and 7z (p7zip / 7-Zip: it unpacks the NSIS installer).
set -euo pipefail

BOXEDWINE_VERSION="${BOXEDWINE_VERSION:-26R1}"
BOXEDWINE_TAG="${BOXEDWINE_TAG:-$BOXEDWINE_VERSION.0}"
BUILD="${BUILD:-MultiThreaded}"
TESS_URL="${TESS_URL:-http://www.peda.com/files/tess_setup.exe}"
TESS_SETUP="${TESS_SETUP:-}"
MESA="${MESA:-1}"
MESA_VERSION="${MESA_VERSION:-20.1.8}"

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="$HERE/cache"   # downloads; reused between runs
WORK="$HERE/work"     # scratch, rebuilt every run
OUT="$HERE/dist"      # the website
WEB="$HERE/web"       # index.html, shell.js, coi-serviceworker.js

BW_RELEASE_URL="https://github.com/danoon2/Boxedwine/releases/download/$BOXEDWINE_TAG/Boxedwine${BOXEDWINE_VERSION}Web.zip"
BW_LICENSE_URL="https://raw.githubusercontent.com/danoon2/Boxedwine/$BOXEDWINE_TAG/license.txt"
# The web release ships a stripped Wine 11. Boxedwine's full Wine 11 file system
# (same build, what the desktop app downloads) supplies the DLL it lacks.
WINE_FULL_URL="https://boxedwine.org/v2/6/TinyCore15Wine11.0.zip"
WINE_EXTRA_FILES=(
    opt/wine/lib/wine/i386-unix/glu32.dll.so   # imported by tess.exe
)
MESA_URL="https://github.com/pal1000/mesa-dist-win/releases/download/$MESA_VERSION/mesa3d-$MESA_VERSION-release-msvc.7z"
MESA_LICENSE_URL="https://gitlab.freedesktop.org/mesa/mesa/-/raw/mesa-$MESA_VERSION/docs/license.html"
APP_DIR="home/username/.wine/drive_c/Tess"   # C:\Tess inside Wine

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for tool in curl unzip zip; do
    command -v "$tool" >/dev/null || die "missing '$tool'"
done
SEVEN=""
for s in 7zz 7z 7za; do command -v "$s" >/dev/null && { SEVEN="$s"; break; }; done
[ -n "$SEVEN" ] || die "missing 7-Zip (7z/7zz/7za); install p7zip-full or 7zip"
case "$BUILD" in MultiThreaded|SingleThreaded) ;; *) die "BUILD must be MultiThreaded or SingleThreaded" ;; esac
[ -f "$WEB/index.html" ] && [ -f "$WEB/shell.js" ] || die "web/index.html and web/shell.js must be next to build.sh"

mkdir -p "$CACHE"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

# fetch URL FILE: download once into the cache.
fetch() {
    if [ -s "$CACHE/$2" ]; then
        echo "cached: $2"
    else
        echo "downloading: $1"
        curl -fL --retry 3 -o "$CACHE/$2.part" "$1"
        mv "$CACHE/$2.part" "$CACHE/$2"
    fi
}

log "Boxedwine $BOXEDWINE_VERSION web release ($BUILD, Wine 11)"
fetch "$BW_RELEASE_URL" "Boxedwine${BOXEDWINE_VERSION}Web.zip"
REL="$CACHE/Boxedwine${BOXEDWINE_VERSION}Web.zip"
unzip -p "$REL" "$BUILD/boxedwine.js"   > "$OUT/boxedwine.js"
unzip -p "$REL" "$BUILD/boxedwine.wasm" > "$OUT/boxedwine.wasm"
unzip -p "$REL" Wine11/boxedwine.zip     > "$OUT/boxedwine.zip"
for f in boxedwine.js boxedwine.wasm boxedwine.zip; do
    [ -s "$OUT/$f" ] || die "$f not found in the release zip"
done
fetch "$BW_LICENSE_URL" "boxedwine-license-$BOXEDWINE_TAG.txt"
cp "$CACHE/boxedwine-license-$BOXEDWINE_TAG.txt" "$OUT/license.txt"

log "Extra Wine 11 DLLs from Boxedwine's full file system"
fetch "$WINE_FULL_URL" "TinyCore15Wine11.0.zip"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
unzip -q -o "$CACHE/TinyCore15Wine11.0.zip" "${WINE_EXTRA_FILES[@]}" -d "$STAGE"

log "Tess installer"
if [ -n "$TESS_SETUP" ]; then
    cp "$TESS_SETUP" "$CACHE/tess_setup.exe"
else
    fetch "$TESS_URL" "tess_setup.exe"
fi

log "Unpacking Tess (NSIS installer, no Wine needed)"
mkdir -p "$WORK/setup"
"$SEVEN" x -y -o"$WORK/setup" "$CACHE/tess_setup.exe" >/dev/null || { rm -f "$CACHE/tess_setup.exe"; die "could not unpack tess_setup.exe, run again"; }
[ -f "$WORK/setup/tess.exe" ] || die "tess.exe not found in the installer"
mkdir -p "$STAGE/$APP_DIR"
cp -a "$WORK/setup/." "$STAGE/$APP_DIR/"
# Installer leftovers: NSIS plug-ins and the uninstaller.
rm -rf "$STAGE/$APP_DIR/\$PLUGINSDIR" "$STAGE/$APP_DIR/Uninstall.exe"

if [ "$MESA" = 1 ]; then
    log "Mesa $MESA_VERSION software OpenGL (for the 3D views)"
    fetch "$MESA_URL" "mesa3d-$MESA_VERSION-release-msvc.7z"
    # Next to tess.exe; shell.js sets WINEDLLOVERRIDES=opengl32=n,b so Wine prefers it.
    "$SEVEN" e -y -o"$STAGE/$APP_DIR" "$CACHE/mesa3d-$MESA_VERSION-release-msvc.7z" \
        x86/opengl32.dll x86/libglapi.dll >/dev/null
    [ -f "$STAGE/$APP_DIR/opengl32.dll" ] && [ -f "$STAGE/$APP_DIR/libglapi.dll" ] \
        || die "x86/opengl32.dll or x86/libglapi.dll not found in the Mesa archive"
    fetch "$MESA_LICENSE_URL" "mesa-license-$MESA_VERSION.html"
    cp "$CACHE/mesa-license-$MESA_VERSION.html" "$OUT/mesa-license.html"
fi

log "Packing tess.zip"
(cd "$STAGE" && zip -q -r -X -9 -n .gif "$OUT/tess.zip" home opt)

log "Web assets"
cp "$WEB"/index.html "$WEB"/shell.js "$OUT/"
if [ "$BUILD" = MultiThreaded ]; then
    cp "$WEB/coi-serviceworker.js" "$OUT/"
else
    # The single-threaded build runs without cross-origin isolation.
    sed -i -e 's|^var MULTI_THREADED = true;|var MULTI_THREADED = false;|' "$OUT/shell.js"
    sed -i -e '/coi-serviceworker\.js/d' "$OUT/index.html"
fi
if [ "$MESA" != 1 ]; then
    sed -i -e '/data-mesa/d' "$OUT/index.html"
    sed -i -e 's|^<!--no-mesa \(.*\)-->$|\1|' "$OUT/index.html"
fi
# Tess's own help pages (its Help menu can't open a browser from inside Wine).
mkdir -p "$OUT/help"
cp -a "$WORK/setup/ReadMe.html" "$WORK/setup/Tutorials.html" "$WORK/setup/img" "$OUT/help/"

rm -rf "$WORK"
log "Done: $OUT"
ls -lh "$OUT"
cat <<EOF

Test locally:  cd dist && python3 -m http.server 8000   then open http://localhost:8000/
Publish:       upload the contents of dist/ to any static host (GitHub Pages works;
               for the MultiThreaded build, coi-serviceworker.js supplies the
               headers it needs).
EOF
