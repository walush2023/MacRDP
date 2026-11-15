#!/bin/bash
# Builds FreeRDP 3 with UDP transport (MS-RDPEUDP) and the native macOS full-screen patch.
# Output: build/freerdp/{bin,lib}  (relocatable: the binary finds its libs via @loader_path/../lib)
set -euo pipefail

VERSION="3.33.1"
SHA256="6b6da1e7217f924b033da6896e70eb4c4a447c3900d03c0d10179062f0a7d495"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/freerdp-src"
PREFIX="$ROOT/build/freerdp"
BREW="$(brew --prefix)"

echo "==> Installing build dependencies with Homebrew"
brew install cmake ninja pkgconf openssl@4 ffmpeg sdl3 sdl3_ttf jpeg-turbo cjson uriparser libusb json-c >/dev/null

mkdir -p "$WORK"
TARBALL="$WORK/FreeRDP-$VERSION.tar.gz"
if [ ! -f "$TARBALL" ]; then
  echo "==> Downloading FreeRDP $VERSION"
  curl -fsSL -o "$TARBALL" "https://github.com/FreeRDP/FreeRDP/archive/refs/tags/$VERSION.tar.gz"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch for $TARBALL"; exit 1; }

SRC="$WORK/FreeRDP-$VERSION"
rm -rf "$SRC"
tar xzf "$TARBALL" -C "$WORK"
echo "==> Applying patches"
for p in "$ROOT"/patches/*.patch; do
  patch -d "$SRC" -p1 --quiet < "$p"
done

echo "==> Configuring"
cmake -S "$SRC" -B "$WORK/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$BREW/opt/openssl@4;$BREW/opt/ffmpeg;$BREW/opt/sdl3;$BREW/opt/sdl3_ttf;$BREW/opt/jpeg-turbo;$BREW/opt/cjson;$BREW" \
  -DWITH_RDPEUDP=ON \
  -DWITH_CLIENT_SDL3=ON -DWITH_CLIENT_SDL2=OFF -DWITH_CLIENT_MAC=OFF -DWITH_X11=OFF \
  -DWITH_SERVER=OFF -DWITH_SHADOW=OFF -DWITH_PROXY=OFF -DWITH_SAMPLE=OFF \
  -DWITH_FFMPEG=ON -DWITH_SWSCALE=ON -DWITH_DSP_FFMPEG=ON -DWITH_APPLE_VIDEOTOOLBOX=ON -DWITH_OPENH264=OFF \
  -DWITH_MACAUDIO=ON -DWITH_CUPS=ON -DWITH_PCSC=ON \
  -DWITH_KRB5=OFF -DWITH_FUSE=OFF -DWITH_MANPAGES=OFF -DWITH_WEBVIEW=OFF -DWITH_SDL_IMAGE_DIALOGS=OFF \
  -DWITH_VERBOSE_WINPR_ASSERT=OFF -DCHANNEL_URBDRC=OFF \
  >"$WORK/cmake.log"

echo "==> Building (a few minutes)"
ninja -C "$WORK/build" >"$WORK/build.log"
rm -rf "$PREFIX"
ninja -C "$WORK/build" install >"$WORK/install.log" 2>&1 || true
[ -x "$PREFIX/bin/sdl-freerdp" ] || { echo "install failed, see $WORK/install.log"; exit 1; }
rm -rf "$PREFIX/include" "$PREFIX/lib/cmake" "$PREFIX/lib/pkgconfig" "$PREFIX/share"

echo "==> Done: $PREFIX/bin/sdl-freerdp"
"$PREFIX/bin/sdl-freerdp" /version 2>/dev/null | head -1 || true
