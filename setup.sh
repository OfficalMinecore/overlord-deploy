#!/bin/bash

# Overlord Management Utility
# Unified tool for Installation, Maintenance, and Decommissioning
# Compatible with: Proxmox (Debian), Ubuntu, Debian

set -e

# Colors for pretty logs
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Please run as root (or use sudo)${NC}"
  exit 1
fi

# ─── FUNCTIONS ──────────────────────────────────────────────────

show_header() {
    clear
    echo -e "${CYAN}🛰️  OVERLORD SYSTEM MANAGER${NC}"
    echo -e "${BLUE}=========================${NC}"
}

# --- INSTALLATION MODULE ---
install_daemon() {
    local mode=$1 # "full" or "binary"
    show_header
    echo -e "${YELLOW}📦 Mode: ${mode^^} INSTALLATION${NC}"
    
    if [ "$mode" == "full" ]; then
        # 1. Env Check
        if [ -z "$DEPLOY_TOKEN" ] || [ -z "$CONVEX_URL" ]; then
            echo -e "${RED}❌ ERROR: Environment variables DEPLOY_TOKEN and CONVEX_URL are required for full install.${NC}"
            echo -e "Usage: DEPLOY_TOKEN=xxx CONVEX_URL=yyy ./setup.sh"
            read -p "Press enter to return..."
            return
        fi

        # 2. Dependencies
        echo -e "🔍 Checking system dependencies..."
        apt-get update -y && apt-get install -y curl sqlite3
    fi

    # 3. Binary Selection
    ARCH=$(uname -m)
    BASE_URL="https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0"
    if [ "$ARCH" == "x86_64" ]; then
        BINARY_URL="${BASE_URL}/overlord-linux-amd64"
    else
        BINARY_URL="${BASE_URL}/overlord-linux-arm64"
    fi

    # 4. Download/Copy Binary
    echo -e "🚚 Installing Binary..."
    if [ -f "./overlord-linux-amd64" ]; then
        echo -e "${GREEN}✨ Using local binary...${NC}"
        cp ./overlord-linux-amd64 /usr/local/bin/overlord-daemon
    else
        curl -L "$BINARY_URL" -o /usr/local/bin/overlord-daemon
    fi
    chmod +x /usr/local/bin/overlord-daemon

    if [ "$mode" == "full" ]; then
        # 5. Service Setup
        echo -e "⚙️  Configuring Service..."
        mkdir -p /var/lib/overlord
        
        # Generation/Persistence of JWT
        JWT_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)
        
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
Environment=JWT_SECRET=$JWT_SECRET
Environment=DB_PATH=/var/lib/overlord/overlord.db

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable overlord-daemon
    fi

    # 6. Start
    echo -e "🚀 Starting Overlord..."
    systemctl restart overlord-daemon
    echo -e "${GREEN}✅ Done!${NC}"
    sleep 2
}

# --- DB MAINTENANCE MODULE ---
db_maintenance() {
    show_header
    echo -e "${YELLOW}💾 DB MAINTENANCE${NC}"
    echo -e "1) Reinstall DB (Wipe and Refresh)"
    echo -e "2) Delete Everything Related to DB"
    echo -e "b) Back"
    read -p "Selection: " db_opt

    case $db_opt in
        1)
            echo -e "${YELLOW}🔄 Reinstalling DB...${NC}"
            systemctl stop overlord-daemon || true
            rm -f /var/lib/overlord/overlord.db*
            systemctl start overlord-daemon
            echo -e "${GREEN}✅ Database reset complete.${NC}"
            ;;
        2)
            echo -e "${RED}⚠️  Deleting ALL database files...${NC}"
            systemctl stop overlord-daemon || true
            rm -rf /var/lib/overlord/*.db*
            echo -e "${GREEN}✅ All database files removed.${NC}"
            ;;
        *) return ;;
    esac
    read -p "Press enter to return..."
}

# --- SELF DESTRUCT MODULE ---
self_destruct() {
    show_header
    echo -e "${RED}☢️ SELF DESTRUCT MENU${NC}"
    echo -e "1) Instant Self Destruct"
    echo -e "2) Timed Self Destruct"
    echo -e "b) Back"
    read -p "Selection: " sd_opt

    if [ "$sd_opt" == "2" ]; then
        read -p "Enter delay in seconds: " delay
        echo -e "${YELLOW}⏳ Self-destruct armed. T-minus $delay seconds...${NC}"
        sleep $delay
    elif [ "$sd_opt" != "1" ]; then
        return
    fi

    echo -e "${RED}🔥 DESTROYING OVERLORD...${NC}"
    systemctl stop overlord-daemon || true
    systemctl disable overlord-daemon || true
    rm -f /etc/systemd/system/overlord-daemon.service
    rm -f /usr/local/bin/overlord-daemon
    rm -rf /var/lib/overlord
    systemctl daemon-reload
    echo -e "${GREEN}💀 Overlord has been purged from this system.${NC}"
    exit 0
}

# --- LOGS MODULE ---
view_logs() {
    show_header
    echo -e "${YELLOW}📜 LOG VIEWER SELECTION${NC}"
    echo -e "1) DB Logs (Database operations)"
    echo -e "2) Web Service Logs (API & Traffic)"
    echo -e "3) Overlord Logs (Detailed combined view)"
    echo -e "b) Back"
    read -p "Selection: " log_opt

    local filter=""
    case $log_opt in
        1) filter="DB|SQLite|ips|attack_logs" ;;
        2) filter="GIN|API|listening|http" ;;
        3) filter="." ;; # Show everything
        *) return ;;
    esac

    show_header
    echo -e "${YELLOW}📜 VIEWING: ${filter}${NC}"
    echo -e "${BLUE}---------------------------------------${NC}"
    journalctl -u overlord-daemon -n 100 --no-pager | grep -E -i "$filter" | tail -n 50
    echo -e "${BLUE}---------------------------------------${NC}"
    echo -e "Press [Ctrl+C] to stop live monitoring..."
    
    # Live view with grep filter
    journalctl -u overlord-daemon -f | grep -E -i --line-buffered "$filter"
    
    read -p "Press enter to return..."
}

# ─── MAIN MENU ──────────────────────────────────────────────────

while true; do
    show_header
    echo -e "1) Install Overlord Daemon"
    echo -e "2) DB Maintenance"
    echo -e "3) Self Destruct"
    echo -e "4) View System Logs"
    echo -e "q) Exit"
    echo -e "${BLUE}-------------------------${NC}"
    read -p "Selection: " choice

    case $choice in
        1)
            show_header
            echo -e "a) Detailed Installation (Full)"
            echo -e "b) Only Binary Installation (Update)"
            echo -e "back) Go Back"
            read -p "Mode: " inst_choice
            if [ "$inst_choice" == "a" ]; then install_daemon "full"; 
            elif [ "$inst_choice" == "b" ]; then install_daemon "binary"; fi
            ;;
        2) db_maintenance ;;
        3) self_destruct ;;
        4) view_logs ;;
        q) exit 0 ;;
        *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
    esac
done
