#!/bin/bash

# Overlord Management Utility - Refactored Version
# Compatible with: Proxmox (Debian), Ubuntu, Debian

# ─── CONFIGURATION & UI ──────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure the script doesn't exit on minor command failures
set +e

# Global Trap: Ignore Ctrl+C in the main menu to prevent accidental exits
trap '' SIGINT

# ─── CORE FUNCTIONS ──────────────────────────────────────────────

show_header() {
    clear
    echo -e "${CYAN}🛰️  OVERLORD SYSTEM MANAGER${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

get_input() {
    local prompt=$1
    local var_name=$2
    printf "${YELLOW}${prompt}${NC} "
    read -r "$var_name"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ This script must be run as root.${NC}"
        exit 1
    fi
}

# ─── SERVICE MODULES ─────────────────────────────────────────────

install_daemon() {
    local mode=$1 
    show_header
    echo -e "${YELLOW}📦 Mode: ${mode^^} INSTALLATION${NC}"
    
    # Validation for Full Install
    if [[ "$mode" == "full" ]]; then
        if [[ -z "$DEPLOY_TOKEN" || -z "$CONVEX_URL" ]]; then
            echo -e "${RED}❌ ERROR: Environment variables missing.${NC}"
            echo -e "Usage: DEPLOY_TOKEN=xx CONVEX_URL=yy $0"
            get_input "Press Enter to return..." dummy
            return
        fi
        echo -e "🔍 Installing system dependencies..."
        apt-get update -qq && apt-get install -y curl sqlite3 >/dev/null 2>&1
    fi

    # Architecture Detection
    local ARCH=$(uname -m)
    local BASE_URL="https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0"
    local BINARY_NAME=$([[ "$ARCH" == "x86_64" ]] && echo "overlord-linux-amd64" || echo "overlord-linux-arm64")
    
    echo -e "🚚 Deploying Binary..."
    if [[ -f "./$BINARY_NAME" ]]; then
        cp "./$BINARY_NAME" /usr/local/bin/overlord-daemon
    else
        curl -fsSL "${BASE_URL}/${BINARY_NAME}" -o /usr/local/bin/overlord-daemon
    fi
    chmod +x /usr/local/bin/overlord-daemon

    # Systemd Configuration
    if [[ "$mode" == "full" ]]; then
        echo -e "⚙️  Generating Systemd Service..."
        mkdir -p /var/lib/overlord
        local JWT_SECRET=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 64)
        
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
        systemctl enable overlord-daemon >/dev/null 2>&1
    fi

    # Post-Install Start
    if [[ -f "/etc/systemd/system/overlord-daemon.service" ]]; then
        echo -e "🚀 Launching Overlord..."
        systemctl restart overlord-daemon
        echo -e "${GREEN}✅ Success!${NC}"
    else
        echo -e "${YELLOW}⚠️ Binary placed. No service file found to start.${NC}"
    fi
    sleep 1.5
}

db_maintenance() {
    show_header
    echo -e "${YELLOW}💾 DB MAINTENANCE${NC}"
    echo -e "1) Reset DB (Wipe & Restart Service)"
    echo -e "2) Total Purge (Delete all DB files)"
    echo -e "b) Back"
    get_input "Selection:" db_opt

    case $db_opt in
        1)
            systemctl stop overlord-daemon
            rm -f /var/lib/overlord/overlord.db*
            systemctl start overlord-daemon
            echo -e "${GREEN}✅ Database has been reset.${NC}"
            ;;
        2)
            systemctl stop overlord-daemon
            rm -rf /var/lib/overlord/*.db*
            echo -e "${GREEN}✅ All database traces removed.${NC}"
            ;;
        *) return ;;
    esac
    get_input "Press Enter to return..." dummy
}

self_destruct() {
    show_header
    echo -e "${RED}☢️  SELF DESTRUCT SYSTEM${NC}"
    echo -e "1) Instant Purge"
    echo -e "2) Timed Purge"
    echo -e "b) Back"
    get_input "Selection:" sd_opt

    if [[ "$sd_opt" == "2" ]]; then
        get_input "Enter delay (seconds):" delay
        [[ $delay =~ ^[0-9]+$ ]] || { echo "Invalid number"; sleep 1; return; }
        echo -e "${YELLOW}⏳ Armed. T-minus $delay seconds...${NC}"
        sleep "$delay"
    elif [[ "$sd_opt" != "1" ]]; then
        return
    fi

    echo -e "${RED}🔥 PURGING OVERLORD FROM DISK...${NC}"
    systemctl stop overlord-daemon >/dev/null 2>&1
    systemctl disable overlord-daemon >/dev/null 2>&1
    rm -f /etc/systemd/system/overlord-daemon.service
    rm -f /usr/local/bin/overlord-daemon
    rm -rf /var/lib/overlord
    systemctl daemon-reload
    echo -e "${GREEN}💀 System purged. Goodbye.${NC}"
    exit 0
}

view_logs() {
    show_header
    echo -e "${YELLOW}📜 SELECT LOG CATEGORY${NC}"
    echo -e "1) Database Logs"
    echo -e "2) Web/API Traffic"
    echo -e "3) Full Debug Stream"
    echo -e "b) Back"
    get_input "Selection:" log_opt

    local filter=""
    case $log_opt in
        1) filter="DB|SQLite|ips|attack_logs" ;;
        2) filter="GIN|API|listening|http" ;;
        3) filter="." ;;
        *) return ;;
    esac

    show_header
    echo -e "${YELLOW}Streaming Logs (Ctrl+C to Stop)${NC}"
    echo -e "${BLUE}-----------------------------------------${NC}"
    
    # Temporarily restore SIGINT for the journalctl process only
    ( trap 'exit 0' SIGINT; journalctl -u overlord-daemon -f -n 50 | grep -E -i --line-buffered "$filter" )
    
    echo -e "\n${GREEN}Returning to menu...${NC}"
    sleep 1
}

# ─── MAIN PROGRAM LOOP ───────────────────────────────────────────

check_root

while true; do
    show_header
    echo -e "1) Install/Update Overlord"
    echo -e "2) Database Maintenance"
    echo -e "3) Self Destruct"
    echo -e "4) View Logs"
    echo -e "q) Exit Utility"
    echo -e "${BLUE}-----------------------------------------${NC}"
    get_input "Selection:" choice

    case $choice in
        1)
            show_header
            echo -e "a) Full Installation (Fresh)"
            echo -e "b) Binary Only (Update)"
            get_input "Mode:" inst_choice
            if [[ "$inst_choice" == "a" ]]; then install_daemon "full"; fi
            if [[ "$inst_choice" == "b" ]]; then install_daemon "binary"; fi
            ;;
        2) db_maintenance ;;
        3) self_destruct ;;
        4) view_logs ;;
        q|Q) clear; exit 0 ;;
        *) continue ;;
    esac
done
