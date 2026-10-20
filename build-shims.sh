#!/data/data/com.termux/files/usr/bin/bash
# Build the two small compatibility libraries used inside termux-docker:
#   libmemfd_shim.so  - provides memfd_create(), missing from the container's old bionic libc
#   libandroid.so     - empty stub so libsqlitejdbc.so can be dlopen()ed (Android's real one is absent)
# Usage: ./build-shims.sh [output-dir]      (default: ~/pz/pzserver/arm64)
set -e

OUT="${1:-$HOME/pz/pzserver/arm64}"
TMP="$(mktemp -d)"
mkdir -p "$OUT"

cat > "$TMP/memfd.c" <<'EOF'
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>

/* 279 = memfd_create on aarch64 */
int memfd_create(const char *name, unsigned int flags) {
    return syscall(279, name, flags);
}
EOF
clang -shared -fPIC -o "$OUT/libmemfd_shim.so" "$TMP/memfd.c"

echo 'void __pz_stub(void){}' > "$TMP/stub.c"
clang -shared -fPIC -Wl,-soname,libandroid.so -o "$OUT/libandroid.so" "$TMP/stub.c"

rm -rf "$TMP"
ls -l "$OUT"/libmemfd_shim.so "$OUT"/libandroid.so
