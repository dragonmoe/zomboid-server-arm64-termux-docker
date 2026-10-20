#!/data/data/com.termux/files/usr/bin/bash
# Launch a Project Zomboid B42 dedicated server inside the Termux container.
# Extra arguments are passed to the server, e.g.:
#   ./start-pz.sh -servername DEADZONE -cachedir "$HOME/pz/DEADZONE"
set -e

PZ_DIR="${PZ_DIR:-$HOME/pz/pzserver}"
JAVA="${JAVA:-/data/data/com.termux/files/usr/lib/jvm/java-25-openjdk/bin/java}"
HEAP="${HEAP:-3g}"

cd "$PZ_DIR"

export LD_LIBRARY_PATH="$PZ_DIR/arm64"
export LD_PRELOAD="$PZ_DIR/arm64/libmemfd_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"

exec "$JAVA" \
  -Djava.awt.headless=true \
  -Xmx"$HEAP" \
  -Dzomboid.steam=0 \
  -Djava.library.path="$PZ_DIR/arm64" \
  -Dorg.lwjgl.librarypath="$PZ_DIR/arm64" \
  -XX:+UseSerialGC \
  --enable-native-access=ALL-UNNAMED \
  -cp "java/:java/projectzomboid.jar" \
  zombie.network.GameServer -nosteam "$@"
