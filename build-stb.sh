#!/data/data/com.termux/files/usr/bin/bash
# Rebuild liblwjgl_stb.so from LWJGL 3.4.1 sources with Termux's clang.
#
# Why: the prebuilt Android build uses TLS descriptors (TLSDESC relocations). The linker in the
# termux-docker image does not resolve them, so the first call into STB jumps to address 0 and
# the JVM dies with SIGSEGV (SEGV_MAPERR, fault addr 0x0).
# Compiled here, with clang targeting an older API level, the library has no TLSDESC relocations.
#
# Usage: ./build-stb.sh [arm64-dir]      (default: ~/pz/pzserver/arm64)
# The original file is saved next to the new one as liblwjgl_stb.so.orig.
set -e

LWJGL_TAG="3.4.1"                       # must match the LWJGL version inside projectzomboid.jar
ARM64_DIR="${1:-$HOME/pz/pzserver/arm64}"
WORK="${WORK:-$HOME/pz/stb-build-work}"
JH="${JAVA_HOME:-$PREFIX/lib/jvm/java-25-openjdk}"

command -v clang >/dev/null || { echo "Install build tools: pkg install -y git clang make llvm"; exit 1; }
MD="$(dirname "$(find "$JH/include" -name jni_md.h | head -1)")"

mkdir -p "$WORK"
cd "$WORK"
[ -d lwjgl3 ] || git clone --depth 1 --branch "$LWJGL_TAG" https://github.com/LWJGL/lwjgl3.git

cd lwjgl3/modules/lwjgl
CFG="$(dirname "$(find . -name LinuxConfig.h | head -1)")"

mkdir -p "$WORK/obj"
rm -f "$WORK"/obj/*
for f in stb/src/generated/c/*.c; do
  clang -c -w -fPIC -O2 -DLWJGL_LINUX \
    -I core/src/main/c -I core/src/generated/c -I stb/src/main/c -I "$CFG" \
    -I "$JH/include" -I "$MD" \
    "$f" -o "$WORK/obj/$(basename "$f" .c).o"
done

clang -shared -o "$WORK/liblwjgl_stb.so" "$WORK"/obj/*.o -lm
llvm-strip --strip-unneeded "$WORK/liblwjgl_stb.so"

echo "TLSDESC relocations (must be 0): $(llvm-readelf -r "$WORK/liblwjgl_stb.so" | grep -ci TLSDESC)"
echo "NEEDED:"; llvm-readelf -d "$WORK/liblwjgl_stb.so" | grep NEEDED
echo "JNI functions: $(llvm-nm -D --defined-only "$WORK/liblwjgl_stb.so" | grep -c Java_org_lwjgl_stb)"

if [ -f "$ARM64_DIR/liblwjgl_stb.so" ] && [ ! -f "$ARM64_DIR/liblwjgl_stb.so.orig" ]; then
  cp "$ARM64_DIR/liblwjgl_stb.so" "$ARM64_DIR/liblwjgl_stb.so.orig"
fi
cp "$WORK/liblwjgl_stb.so" "$ARM64_DIR/liblwjgl_stb.so"
echo "Installed to $ARM64_DIR/liblwjgl_stb.so"
