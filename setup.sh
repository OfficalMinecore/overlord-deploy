#!/bin/bash

# =================================================================
# OVERLORD SYSTEM MANAGER (Stable Version)
# =================================================================

# --- 1. Environment & Safety ---
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set +e             # Don't exit on error
trap '' SIGINT      # Ignore Ctrl+C in the main menu loop

# --- 2. UI Styling ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 3. Helper Functions ---
show_header() {
    clear
    echo -e "${CYAN}🛰️  OVERLORD SYSTEM MANAGER${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

pause() {
    echo -e "\n${BLUE}-----------------------------------------${NC}"
    read -p "Press [Enter] to return to menu..." dummy
}

# --- 4. Logic Modules ---

install_process() {
    local mode=$1
    show_header
    echo -e "${YELLOW}📦 Mode: ${mode^^} INSTALLATION${NC}"

    if [ "$mode" == "full" ]; then
        # Check env vars
        if [[ -z "$DEPLOY_TOKEN" || -z "$CONVEX_URL" ]]; then
            echo -e "${RED}❌ Missing DEPLOY_TOKEN or CONVEX_URL env vars.${NC}"
            pause; return
        fi
        echo -e "🔍 Installing dependencies (curl, sqlite3)..."
        apt-get update -qq && apt-get install -y curl sqlite3 >/dev/null 2>&1
    fi

    # Arch check
    ARCH=$(uname -m)
    BINARY=$([[ "$ARCH" == "x86_64" ]] && echo "overlord-linux-amd64" || echo "overlord-linux-arm64")
    
    echo -e "🚚 Fetching binary..."
    curl -L "https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0/$BINARY" -o /usr/local/bin/overlord-daemon
    chmod +x /usr/local/bin/overlord-daemon

    if [ "$mode" == "full" ]; then
        echo -e "⚙️  Creating service..."
        mkdir -p /var/lib/overlord
        SECRET=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 64)
        
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
Environment=JWT_SECRET=$SECRET
Environment=DB_PATH=/var/lib/overlord/overlord.db

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable overlord-daemon >/dev/null 2>&1
    fi

    systemctl restart overlord-daemon
    echo -e "${GREEN}✅ Done!${NC}"
    sleep 2
}

manage_logs() {
    show_header
    echo -e "${YELLOW}📜 View Logs:${NC}"
    echo -e "1) Database  2) API Traffic  3) Full Stream  b) Back"
    printf "${CYAN}Choice:${NC} "
    read -r log_choice

    case $log_choice in
        1) filter="DB|SQLite" ;;
        2) filter="GIN|API|http" ;;
        3) filter="." ;;
        *) return ;;
    esac

    echo -e "${YELLOW}Starting stream (Press Ctrl+C to stop)...${NC}"
    echo -e "${BLUE}-----------------------------------------${NC}"
    
    # Temporarily restore Ctrl+C for journalctl
    trap - SIGINT
    journalctl -u overlord-daemon -f -n 50 | grep -E -i --line-buffered "$filter"
    trap '' SIGINT # Re-ignore Ctrl+C
    
    pause
}

self_destruct() {
    show_header
    echo -e "${RED}☢️  WARNING: THIS WILL PURGE THE SYSTEM${NC}"
    read -p "Type 'DESTROY' to confirm: " confirm
    if [ "$confirm" == "DESTROY" ]; then
        systemctl stop overlord-daemon 2>/dev/null
        systemctl disable overlord-daemon 2>/dev/null
        rm -rf /etc/systemd/system/overlord-daemon.service /usr/local/bin/overlord-daemon /var/lib/overlord
        systemctl daemon-reload
        echo -e "${GREEN}Purge complete.${NC}"
        exit 0
    fi
}

# --- 5. Main Execution Loop ---

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Please run as root.${NC}"
    exit 1
fi

while true; do
    show_header
    echo -e "1) Full Installation"
    echo -e "2) Update Binary Only"
    echo -e "3) Database Maintenance"
    echo -e "4) View System Logs"
    echo -e "5) Self Destruct"
    echo -e "q) Quit"
    echo -e "${BLUE}-----------------------------------------${NC}"
    printf "${YELLOW}Selection:${NC} "
    
    # This read command blocks the loop, stopping the flickering.
    read -r choice

    case $choice in
        1) install_process "full" ;;
        2) install_process "binary" ;;
        3) 
            show_header
            echo -e "1) Wipe DB (Restart)  2) Back"
            read -r db_opt
            if [ "$db_opt" == "1" ]; then
                systemctl stop overlord-daemon
                rm -f /var/lib/overlord/overlord.db*
                systemctl start overlord-daemon
                echo -e "${GREEN}DB Wiped.${NC}"; sleep 1
            fi
            ;;
        4) manage_logs ;;
        5) self_destruct ;;
        q|Q) clear; exit 0 ;;
        *) 
            # If the user hits enter or types garbage, do nothing (no flicker)
            continue 
            ;;
    esac
done
