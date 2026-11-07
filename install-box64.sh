
#!/data/data/com.termux/files/usr/bin/bash

set -e

# =================================
# BOX64 INSTALLER FOR TERMUX
# Ubuntu ARM64 / Proot-Distro
# =================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================"
echo "       BOX64 INSTALLER"
echo "================================"

# Check architecture
ARCH=$(uname -m)

if [ "$ARCH" != "aarch64" ]; then
    echo -e "${RED}Error: ARM64 device required.${NC}"
    exit 1
fi

echo "[1/4] Installing Termux dependencies..."

pkg update -y
pkg install proot-distro -y

# Install Ubuntu
if ! proot-distro list | grep -q 'ubuntu'; then
    echo "[2/4] Installing Ubuntu..."
    proot-distro install ubuntu
else
    echo "Ubuntu already installed."
fi

echo "[3/4] Building Box64 inside Ubuntu..."

proot-distro login ubuntu -- bash -c '

set -e

apt update

apt install -y \
    git \
    cmake \
    build-essential \
    python3 \
    wget \
    curl

cd /root

if [ -d box64/.git ]; then
    echo "Updating Box64 source..."
    cd box64
    git pull
else
    git clone https://github.com/ptitSeb/box64.git
    cd box64
fi

mkdir -p build
cd build

cmake .. \
    -D ARM64=1 \
    -D CMAKE_C_COMPILER=gcc \
    -D BAD_SIGNAL=ON \
    -D CMAKE_BUILD_TYPE=Release

# Limit compilation jobs to reduce RAM usage
make -j2

make install

ldconfig

echo ""
echo "Box64 installation completed!"

'

echo "[4/4] Checking installation..."

proot-distro login ubuntu -- box64 -v

echo -e "${GREEN}"
echo "================================"
echo "       INSTALLATION DONE"
echo "================================"
echo -e "${NC}"

echo "Run Ubuntu:"
echo "proot-distro login ubuntu"

echo "Check Box64:"
echo "box64 -v"

