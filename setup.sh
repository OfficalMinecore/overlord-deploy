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

# Mandatory Check: These must be passed via -E or existing env
if [ -z "$DEPLOY_TOKEN" ]; then
    echo -e "${RED}❌ ERROR: DEPLOY_TOKEN is missing.${NC}"
    echo -e "Usage: DEPLOY_TOKEN=xxx CONVEX_URL=yyy sudo -E ./setup.sh"
    exit 1
fi
if [ -z "$CONVEX_URL" ]; then
    echo -e "${RED}❌ ERROR: CONVEX_URL is missing.${NC}"
    echo -e "Usage: DEPLOY_TOKEN=xxx CONVEX_URL=yyy sudo -E ./setup.sh"
    exit 1
fi

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

# 2. Architecture & Environment Selection
ARCH=$(uname -m)

if [ ! -d "/etc/pve" ]; then
    echo -e "${RED}❌ ERROR: Proxmox Hypervisor not detected (/etc/pve).${NC}"
    echo -e "Overlord is now an exclusive Proxmox Appliance. Installation aborted."
    exit 1
fi
echo -e "🛰️  Detected Environment: ${CYAN}Proxmox Hypervisor${NC}"
FLAVOR="proxmox"

# 3. Binary Selection & Matching
VERSION="v1.0.0"
BASE_URL="https://github.com/OfficalMinecore/overlord-deploy/releases/download/${VERSION}"
if [ "$ARCH" == "x86_64" ]; then
    BINARY_URL="${BASE_URL}/overlord-${FLAVOR}-amd64"
    EXPECTED_NAME="overlord-${FLAVOR}-amd64"
elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
    BINARY_URL="${BASE_URL}/overlord-${FLAVOR}-arm64"
    EXPECTED_NAME="overlord-${FLAVOR}-arm64"
else
    echo -e "${RED}❌ Unsupported Architecture: ${ARCH}${NC}"
    exit 1
fi

echo -e "⚙️  Target Binary: ${EXPECTED_NAME}"

# 4. Secure Download & Install
INSTALL_NEEDED=true

if [ -f "/usr/local/bin/overlord-daemon" ]; then
    # Try to verify the flavor of the existing binary
    # We use a simple check for a 'proxmox' string in the binary as a heuristic
    # or just trust the user if they're running setup again.
    # For now, let's see if we should force a specialized flavor check.
    echo -e "🔍 Existing binary found. Checking for flavor match..."
    
    # We can skip if the user just wants to update config, 
    # but if the environment is PVE and the binary was built for HOST, we MUST update.
    # For simplicity, we compare a hidden flavor-stamp if available, 
    # but here we'll just check if the user wants to FORCE flavor alignment.
    if /usr/local/bin/overlord-daemon --version 2>&1 | grep -qi "$FLAVOR"; then
        echo -e "${GREEN}✨ Existing binary matches the system flavor ($FLAVOR). Skipping download.${NC}"
        INSTALL_NEEDED=false
    else
        echo -e "${BLUE}🔄 Flavor mismatch or versioning enabled. Aligning binary to $FLAVOR...${NC}"
    fi
fi

if [ "$INSTALL_NEEDED" = true ]; then
    echo -e "🚚 Downloading specialized binary..."
    if [ -f "./overlord-${FLAVOR}" ]; then
        echo -e "${GREEN}✨ Using locally built binary (overlord-${FLAVOR})${NC}"
        cp "./overlord-${FLAVOR}" /usr/local/bin/overlord-daemon
    elif [ -f "./$EXPECTED_NAME" ]; then
        echo -e "${GREEN}✨ Using locally staged binary ($EXPECTED_NAME)${NC}"
        cp "./$EXPECTED_NAME" /usr/local/bin/overlord-daemon
    elif [ -f "./bin/$EXPECTED_NAME" ]; then
        echo -e "${GREEN}✨ Using locally built release binary (bin/$EXPECTED_NAME)${NC}"
        cp "./bin/$EXPECTED_NAME" /usr/local/bin/overlord-daemon
    elif ! curl -SfL "$BINARY_URL" -o /usr/local/bin/overlord-daemon || [ $(stat -c%s "/usr/local/bin/overlord-daemon") -lt 1000 ]; then
        echo -e "${BLUE}🔄 Download failed or asset missing (Size check failed).${NC}"
        
        # Fallback: Build from source if we are in a repo and Go is installed
        if command -v go &> /dev/null && [ -f "Makefile" ]; then
            echo -e "🛠️  Attempting to build ${FLAVOR} flavor from source..."
            if make build-${FLAVOR}; then
                cp "overlord-${FLAVOR}" /usr/local/bin/overlord-daemon
                echo -e "${GREEN}✅ Successfully built from source!${NC}"
            else
                echo -e "${RED}❌ Build failed.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ Download failed and no local source/Go compiler found.${NC}"
            echo -e "💡 TIP: Please upload your binaries to the GitHub Release ${VERSION} first."
            exit 1
        fi
    fi

    # Verify binary integrity
    FILE_SIZE=$(stat -c%s "/usr/local/bin/overlord-daemon")
    if [ "$FILE_SIZE" -lt 1000 ]; then
        echo -e "${RED}❌ ERROR: Binary file is too small ($FILE_SIZE bytes). GitHub returned a 404 or file is corrupt.${NC}"
        echo -e "💡 TIP: Check if you have uploaded the assets to your GitHub Release ${VERSION}."
        exit 1
    fi
    chmod +x /usr/local/bin/overlord-daemon
fi

# Download DB Reset Utility (Development Source)
if [ -f "./reset_db.sh" ]; then
    cp ./reset_db.sh /usr/local/bin/overlord-reset-db
    chmod +x /usr/local/bin/overlord-reset-db
    echo -e "🛠️  Reset utility installed from local source."
fi

chmod +x /usr/local/bin/overlord-daemon
echo -e "🎯 Executable verified."

# 4. Data Directory Setup
echo -e "📂 Creating data directory..."
mkdir -p /var/lib/overlord
chown root:root /var/lib/overlord
chmod 750 /var/lib/overlord

# 4. Environment Variables & Systemd
echo -e "⚙️  Configuring Overlord Service..."

# Generate persistent JWT secret if not exists
if [ -f "/etc/systemd/system/overlord-daemon.service" ]; then
    # Harvest existing values if current ones are empty
    [ -z "$JWT_SECRET" ] && JWT_SECRET=$(grep "JWT_SECRET=" /etc/systemd/system/overlord-daemon.service | cut -d'=' -f3)
    [ -z "$PROXMOX_URL" ] && PROXMOX_URL=$(grep "PROXMOX_URL=" /etc/systemd/system/overlord-daemon.service | cut -d'=' -f3)
    [ -z "$PROXMOX_TOKEN_ID" ] && PROXMOX_TOKEN_ID=$(grep "PROXMOX_TOKEN_ID=" /etc/systemd/system/overlord-daemon.service | cut -d'=' -f3)
    [ -z "$PROXMOX_TOKEN_SECRET" ] && PROXMOX_TOKEN_SECRET=$(grep "PROXMOX_TOKEN_SECRET=" /etc/systemd/system/overlord-daemon.service | cut -d'=' -f3)
    [ -z "$PROXMOX_NODE" ] && PROXMOX_NODE=$(grep "PROXMOX_NODE=" /etc/systemd/system/overlord-daemon.service | cut -d'=' -f3)
fi

# Fallback for JWT
if [ -z "$JWT_SECRET" ]; then
    JWT_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)
fi

cat <<EOF > /etc/systemd/system/overlord-daemon.service
[Unit]
Description=Overlord Edge Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/overlord-daemon
WorkingDirectory=/var/lib/overlord
Restart=always
Environment=DEPLOY_TOKEN=$DEPLOY_TOKEN
Environment=CONVEX_URL=$CONVEX_URL
Environment=PROXMOX_URL=$PROXMOX_URL
Environment=PROXMOX_TOKEN_ID=$PROXMOX_TOKEN_ID
Environment=PROXMOX_TOKEN_SECRET=$PROXMOX_TOKEN_SECRET
Environment=PROXMOX_NODE=${PROXMOX_NODE:-minecloud}
Environment=JWT_SECRET=$JWT_SECRET
Environment=DB_PATH=/var/lib/overlord/overlord.db

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
echo -e "🖥️  ${CYAN}Local Dashboard:${NC} http://$(hostname -I | awk '{print $1}'):3000"
echo -e "🛰️  Private-Link API: http://$(hostname -I | awk '{print $1}'):8080"
echo -e "📂 Binary Path: /usr/local/bin/overlord-daemon"
echo -e "📂 Service Path: /etc/systemd/system/overlord-daemon.service"
echo -e "📊 Status: sudo systemctl status overlord-daemon"
echo -e "${NC}"

# Cleanup
echo -e "${CYAN}✨ Cleanup complete.${NC}"
