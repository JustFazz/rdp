
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

# URL script utama
SCRIPT_URL="https://raw.githubusercontent.com/JustFazz/rdp/main/install-bedrock.sh"

# Cache sementara di Termux Home
CACHE_DIR="$HOME/bds"
CACHE_FILE="$CACHE_DIR/bds.sh"


echo "[BDS] Preparing installer..."

mkdir -p "$CACHE_DIR"

# Download script utama
echo "[BDS] Downloading BDS manager..."

curl -fL "$SCRIPT_URL" -o "$CACHE_FILE"

cp $CACHE_FILE $HOME/install-bedrock.sh

chmod +x $HOME/install-bedrock.sh

cat > "$PREFIX/bin/bds" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec bash "$HOME/install-bedrock.sh" "$@"
EOF

chmod +x "$PREFIX/bin/bds"

cat > $HOME/bedrock/run-bds.sh <<'EOF'
#!/usr/bin/env bash

# Box64 optimization
export BOX64_DYNAREC=1
export BOX64_DYNAREC_BIGBLOCK=2
export BOX64_DYNAREC_FASTNAN=1
export BOX64_DYNAREC_FASTROUND=1
export BOX64_DYNAREC_NATIVEFLAGS=1

# Dynamic cache
export BOX64_DYNACACHE=1
export BOX64_DYNACACHE_FOLDER="$HOME/.cache/box64"

# CALL/RET optimization (experimental)
export BOX64_DYNAREC_CALLRET=1

mkdir -p "$BOX64_DYNACACHE_FOLDER"

# Start BDS
exec box64 ./bedrock_server
EOF

chmod +x run-bds.sh

# Masuk Ubuntu dan instalasi
echo "[BDS] Installing into Ubuntu..."

proot-distro login --shared-home ubuntu -- bash -s <<'UBUNTU'

set -euo pipefail

INSTALL_DIR="/usr/local/lib/bds"
BIN_DIR="/usr/local/bin"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Salin script dari shared home Termux
install -m 755 /root/bds/bds.sh \
    "$INSTALL_DIR/bds.sh"

# Buat command bds
cat > "$BIN_DIR/bds" <<'EOF'
#!/bin/bash
exec bash /usr/local/lib/bds/bds.sh "$@"
EOF

chmod +x "$BIN_DIR/bds"

echo ""
echo "[BDS] Installation completed!"
echo "[BDS] Command available: bds"

UBUNTU

echo "[BDS] Done!"
echo "Jalankan [bds instal] untuk menginstal bedrock"