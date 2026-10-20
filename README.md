# zomboid-server-arm64-docker

Run a **Project Zomboid Build 42 dedicated server natively on a regular ARM64 Linux server** (tested on an Oracle Cloud Ampere A1 instance, Ubuntu, kernel 7.0.0-1013-oracle, 4 KB pages) with no box64, FEX or QEMU.

This builds on [nikiiiii-ii/zomboid-server-native-arm64](https://github.com/nikiiiii-ii/zomboid-server-native-arm64), which does the same inside Termux on an Android phone. Everything in this repo is about the extra problems that appear when you move that setup from a phone to a normal ARM64 Linux host.

> **Status:** works for the author's setup. A player can join and chunks load without crashes. See [What is and isn't verified](#what-is-and-isnt-verified).

---

## How it works

The ARM64 natives shipped by Project Zomboid (`natives/android/arm64-v8a`) and the LWJGL build from Zomdroid are **Android (bionic) libraries**. A regular Linux host uses glibc, which cannot load them (`library "libc.so.6" not found`, and the reverse). So instead of translating instructions, we give the server the userland it was built for:

```
Ubuntu arm64 host (Oracle Ampere)
 └─ Docker: termux/termux-docker:aarch64        (Termux userland, bionic libc)
     └─ OpenJDK 25 from Termux
         └─ projectzomboid.jar  +  Android arm64 natives
```

The server runs at native speed because the CPU architecture is the same. Only the C library differs, and that is handled by the container.

The container's bionic is older than the one on a recent phone, which causes three problems that this repo fixes:

| Problem | Symptom | Fix |
|---|---|---|
| `memfd_create` missing from container libc | `dlopen failed: cannot locate symbol "memfd_create"` when loading `liblwjgl.so` | `libmemfd_shim.so` via `LD_PRELOAD` ([build-shims.sh](build-shims.sh)) |
| `libandroid.so` missing | `dlopen failed: library "libandroid.so" not found` when loading `libsqlitejdbc.so` | empty stub `libandroid.so` ([build-shims.sh](build-shims.sh)) |
| Linker does not support TLS descriptors | SIGSEGV, fault addr `0x0`, thread `LoadChunk`, right after a player connects | rebuild `liblwjgl_stb.so` from source ([build-stb.sh](build-stb.sh)) |

---

## Requirements

- ARM64 Linux host with Docker, at least 6 GB RAM (the author uses `-Xmx3g`)
- ~10 GB free disk
- A Steam account that **owns Project Zomboid** (the ARM natives are in the game depot, not the dedicated-server depot)
- UDP ports 16261 and 16262 open (cloud security list **and** host firewall)

This repo contains no game files or binaries. You obtain the natives yourself.

---

## 1. Host and container

```bash
sudo apt update && sudo apt install -y docker.io
sudo mkdir -p /srv/pz-data            # use any path you like
sudo chown -R 1000:1000 /srv/pz-data

sudo docker run -dit --name pz \
  -p 16261:16261/udp -p 16262:16262/udp \
  -v /srv/pz-data:/data/data/com.termux/files/home/pz \
  --restart unless-stopped \
  termux/termux-docker:aarch64 sleep infinity
```

`sleep infinity` keeps the container alive; without a command the container exits immediately.

If startup fails with `address already in use`, something else holds the port: `sudo ss -ulpn | grep 16261`.

> During debugging the container was also run with `--security-opt seccomp=unconfined --cap-add SYS_PTRACE` (needed for `gdb`/`strace`). The crash was **not** caused by seccomp and these flags are not required for normal operation, but this has not been tested with every setup.

### Getting a shell

```bash
sudo docker exec -it pz /entrypoint.sh bash -l
```

This drops to the `system` user. Two things that **do not** work here:

- `pkg` refuses to run as root (`Cannot run 'pkg' command as root`).
- `docker exec -u system ...` fails with `openat etc/passwd: path escapes from parent`, because `/etc` in the image is a symlink.

### Packages (inside the container, as `system`)

```bash
pkg update && pkg upgrade -y
pkg install -y openjdk-25 tmux nano unzip file clang llvm git make binutils
```

Project Zomboid 42.x is compiled for Java 25 (class file version 69). The container may also have Java 21 installed and first in `PATH`; that gives
`UnsupportedClassVersionError ... class file version 69.0`. The launcher script uses the full path to the Java 25 binary to avoid this.

---

## 2. Server files and natives

Server files, game natives and LWJGL libraries are obtained the same way as in the reference repository, so follow its sections:

- Server files (depot `380870`, anonymous) with DepotDownloader.
- `natives/android/arm64-v8a` from the game depot (`108600`, needs a Steam account that owns the game), copied into `~/pz/pzserver/arm64`.
- The LWJGL 3.4.1 `*.so` files from the Zomdroid APK (`android-arm64-v8a/lwjgl-3.4.1/`), copied into `~/pz/pzserver/arm64`.

The DepotDownloader steps were not re-run inside this container by the author (server files were copied from an existing working install), so check the reference repo for the exact commands.

Layout expected by the launcher:

```
~/pz/pzserver/
├── java/projectzomboid.jar
└── arm64/
    ├── libRakNet64.so  libZNetNoSteam64.so  libPZPathFind64.so
    ├── libPZPopMan64.so  libPZBullet64.so  libPZClipper64.so
    ├── libjassimp64.so  libLighting64.so  libfmodintegration64.so
    ├── liblwjgl.so  liblwjgl_opengl.so  liblwjgl_stb.so
    ├── libsqlitejdbc.so         <- Android aarch64 build of sqlite-jdbc (TODO: document source)
    ├── libmemfd_shim.so         <- built by build-shims.sh
    └── libandroid.so            <- built by build-shims.sh
```

`libsqlitejdbc.so` is needed because the server's SQLite JDBC driver reports `os.name=Linux-Android` under Termux and otherwise fails with `NativeLibraryNotFoundException ... Linux-Android/aarch64`.

---

## 3. Apply the fixes

```bash
cd ~/pz
# copy build-shims.sh, build-stb.sh, start-pz.sh here, then:
chmod +x *.sh
./build-shims.sh          # creates libmemfd_shim.so and libandroid.so in ~/pz/pzserver/arm64
./build-stb.sh            # rebuilds liblwjgl_stb.so from LWJGL 3.4.1 sources (backs up the original)
```

`build-stb.sh` ends by printing the number of TLSDESC relocations. **It must be `0`.**
The script keeps the version of LWJGL it builds (`LWJGL_TAG`) as `3.4.1`; set it to the LWJGL version bundled in your `projectzomboid.jar` (`java -cp "java/*" org.lwjgl.Version`).

---

## 4. Run

```bash
tmux new -s pz
~/pz/start-pz.sh -servername MYSERVER -cachedir "$HOME/pz/MYSERVER"
```

Detach with `Ctrl+B`, then `D`. Re-attach with `tmux attach -t pz`.

First run asks for an admin password. Settings live under the cache directory (`Server/<name>.ini`, `Server/<name>_SandboxVars.lua`).

Environment variables for `start-pz.sh`: `PZ_DIR` (default `~/pz/pzserver`), `JAVA`, `HEAP` (default `3g`).

Clients need `-nosteam` in their Steam launch options and add the server manually by IP and port 16261.

---

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| `[LWJGL] [ERROR] Incompatible Java and native library versions detected` | Harmless. Printed on every LWJGL library load, even on a working phone setup. The jar reports `3.4.1-snapshot`, the natives come from the `3.4.1` release. | Ignore |
| `libjemalloc.so not found` / `Failed to instantiate memory allocator` | Harmless. LWJGL falls back to the system allocator. | Ignore |
| `UnsatisfiedLinkError ... n_saveCell` (`libPZPopMan64.so`) | Known limitation of the ARM natives (see reference repo): per-cell zombie state is not saved | Ignore |
| `No packet handler for type: ...` | Log noise | Ignore |
| `dlopen failed: library "libc.so.6" not found` | A **glibc** LWJGL library (for example from lwjgl.org `linux/arm64`) replaced an Android one | Restore the Android build; check with `llvm-readelf -d lib.so \| grep NEEDED` (must list `libc.so`, not `libc.so.6`) |
| `cannot locate symbol "memfd_create"` | Container libc too old | `libmemfd_shim.so` + `LD_PRELOAD` |
| `library "libandroid.so" not found` | No Android runtime libs | stub `libandroid.so` + `LD_LIBRARY_PATH` |
| `no such table: whitelist` / `role` | Empty `.db` left over from an earlier failed start | Move `~/Zomboid/db/<server>.db` aside and restart |
| `UnsupportedClassVersionError ... 69.0` | Java 21 used instead of 25 | Use the full path to the Java 25 binary |
| `SIGSEGV, SEGV_MAPERR, fault addr 0x0` in `LoadChunk` | TLSDESC in `liblwjgl_stb.so` | `build-stb.sh` |

### Diagnosing the TLSDESC crash yourself

```bash
# any TLS descriptor relocations?  (non-zero = trouble on this linker)
for f in arm64/*.so; do echo "$f: $(llvm-readelf -r "$f" 2>/dev/null | grep -ci TLSDESC)"; done

# does the linker know about them?  (compare with a phone that works)
strings /system/bin/linker64 | grep -i tlsdesc
```

Under `gdb` the crashing frame looks like this: an `adrp/ldr/add/blr x1` sequence followed by `mrs xN, tpidr_el0`, where `x1` is `0`. That is the standard AArch64 TLS-descriptor call sequence.

```bash
pkg install -y gdb
gdb -q --args java --class-path "java/*" -Dorg.lwjgl.librarypath=$PWD/arm64 ... Test.java
(gdb) handle SIGSEGV stop print nopass
(gdb) run
(gdb) bt 8
(gdb) frame 1
(gdb) disassemble
```

(`gdb` needs the container to have `SYS_PTRACE`.)

---

## What is and isn't verified

Verified on the author's machine (Oracle Ampere, Ubuntu, Docker, `termux/termux-docker:aarch64`, PZ B42, OpenJDK 25.0.4):

- Server starts, accepts a connection, loads chunks without crashing after the three fixes.
- `liblwjgl_stb.so` built by `build-stb.sh` has 0 TLSDESC relocations, the same 224 `Java_org_lwjgl_stb_*` JNI functions as the Zomdroid build, and only `libm.so`, `libdl.so`, `libc.so` as dependencies.

Not verified:

- Behaviour with many players or heavy mods.
- Running without `seccomp=unconfined`/`SYS_PTRACE` was not isolated as a separate test.
- The build uses unpatched LWJGL 3.4.1 sources. Zomdroid applies its own patches (see [zomdroid-dependencies](https://github.com/udarmolota/zomdroid-dependencies)); the STB module does not appear to depend on them, but this was not checked against the patch contents.
- Other containers/images, other Ampere kernels, other PZ versions.

---

## Credits

- [nikiiiii-ii/zomboid-server-native-arm64](https://github.com/nikiiiii-ii/zomboid-server-native-arm64): the native-on-Android approach this builds on
- [Zomdroid](https://github.com/udarmolota/zomdroid) and [zomdroid-dependencies](https://github.com/udarmolota/zomdroid-dependencies): Android LWJGL build
- [termux/termux-docker](https://github.com/termux/termux-docker)
- [LWJGL](https://github.com/LWJGL/lwjgl3)

Not affiliated with The Indie Stone. Project Zomboid is theirs; buy the game.
