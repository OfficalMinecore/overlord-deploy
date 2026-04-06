#!/bin/bash

# Overlord Private-Link: Automated Edge Installer
# Compatible with: Proxmox (Debian), Ubuntu, Debian

set -e

# Colors for pretty logs
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}🛰️  Overlord Private-Link Edge Installer${NC}"
echo -e "${BLUE}---------------------------------------${NC}"

# Check for root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Please run as root (or use sudo)${NC}"
  exit 1
fi

# 1. Dependency Resolution
echo -e "🔍 Checking system dependencies..."

PACKAGES="curl"
MISSING_PACKAGES=""

for pkg in $PACKAGES; do
    if ! command -v $pkg &> /dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done

if [ ! -z "$MISSING_PACKAGES" ]; then
    echo -e "📦 Installing missing packages: $MISSING_PACKAGES..."
    apt-get update -y && apt-get install -y $MISSING_PACKAGES
fi

# 2. Architecture & Binary Selection
ARCH=$(uname -m)
BASE_URL="https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0"

if [ "$ARCH" == "x86_64" ]; then
    BINARY_URL="${BASE_URL}/overlord-linux-amd64"
    echo -e "🖥️  Detected Architecture: x86_64 (AMD64)"
elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
    BINARY_URL="${BASE_URL}/overlord-linux-arm64"
    echo -e "📱 Detected Architecture: arm64"
else
    echo -e "${RED}❌ Unsupported Architecture: ${ARCH}${NC}"
    exit 1
fi

# 3. Secure Download & Install
echo -e "🚚 Downloading Overlord-Daemon (Binary Release)..."
if ! curl -L "$BINARY_URL" -o /usr/local/bin/overlord-daemon; then
    echo -e "${RED}❌ Download failed! Check your internet connection or the release URL.${NC}"
    exit 1
fi

# Verify binary integrity
FILE_SIZE=$(stat -c%s "/usr/local/bin/overlord-daemon")
if [ "$FILE_SIZE" -lt 1000 ]; then
    echo -e "${RED}❌ ERROR: Downloaded file is too small ($FILE_SIZE bytes).${NC}"
    echo -e "${RED}It is likely a 404 page. Check if the release exists at:${NC}"
    echo -e "${CYAN}$BINARY_URL${NC}"
    exit 1
fi

chmod +x /usr/local/bin/overlord-daemon
echo -e "🎯 Optimized executable installed."

# 4. Environment Variables & Systemd
echo -e "⚙️  Configuring Overlord Service..."
cat <<EOF > /etc/systemd/system/overlord-daemon.service
[Unit]
Description=Overlord Edge Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/overlord-daemon
Restart=always
Environment=DEPLOY_TOKEN=$DEPLOY_TOKEN
Environment=CONVEX_URL=$CONVEX_URL
Environment=PROXMOX_URL=$PROXMOX_URL
Environment=PROXMOX_TOKEN_ID=$PROXMOX_TOKEN_ID
Environment=PROXMOX_TOKEN_SECRET=$PROXMOX_TOKEN_SECRET

[Install]
WantedBy=multi-user.target
EOF

# 6. Service Management
echo -e "🚀 Starting Overlord Service..."
systemctl stop overlord-daemon || true
systemctl daemon-reload
systemctl enable overlord-daemon
systemctl start overlord-daemon

# 7. Verification
echo -e "🔍 Verifying binary execution..."
sleep 2

if systemctl is-active --quiet overlord-daemon; then
    echo -e "${GREEN}✅ DAEMON IS RUNNING!${NC}"
    echo -e "📄 Last 5 logs:"
    journalctl -u overlord-daemon -n 5 --no-pager
else
    echo -e "${RED}❌ DAEMON FAILED TO START!${NC}"
    echo -e "⚠️  Check logs: journalctl -u overlord-daemon -n 20"
    exit 1
fi

echo -e "${BLUE}---------------------------------------${NC}"
echo -e "${GREEN}✅ INSTALLATION COMPLETE!${NC}"
echo -e "🛰️  Private-Link API: http://$(hostname -I | awk '{print $1}'):8080"
echo -e "📂 Binary Path: /usr/local/bin/overlord-daemon"
echo -e "📂 Service Path: /etc/systemd/system/overlord-daemon.service"
echo -e "📂 Database Path: /var/lib/overlord/overlord.db (if configured)"
echo -e "📊 Status: sudo systemctl status overlord-daemon"
echo -e "${NC}"

# Cleanup
rm -rf "$WS_DIR"
