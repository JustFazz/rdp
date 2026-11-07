
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

# URL script utama
SCRIPT_URL="https://raw.githubusercontent.com/JustFazz/rdp/main/install-bedrock.sh"

# Cache sementara di Termux Home
CACHE_DIR="$HOME/.cache/bds"
CACHE_FILE="$CACHE_DIR/bds.sh"

echo "[BDS] Preparing installer..."

mkdir -p "$CACHE_DIR"

# Download script utama
echo "[BDS] Downloading BDS manager..."

curl -fL "$SCRIPT_URL" -o "$CACHE_FILE"

# Masuk Ubuntu dan instalasi
echo "[BDS] Installing into Ubuntu..."

proot-distro login --shared-home ubuntu -- bash -s <<'UBUNTU'

set -euo pipefail

INSTALL_DIR="/usr/local/lib/bds"
BIN_DIR="/usr/local/bin"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Salin script dari shared home Termux
install -m 755 /root/.cache/bds/bds.sh \
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

# Bersihkan cache Termux
rm -rf "$CACHE_DIR"

echo "[BDS] Done!"
