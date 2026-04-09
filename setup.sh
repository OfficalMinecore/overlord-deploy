#!/bin/bash

# Overlord Management Utility
# Optimized to prevent screen flickering and handle signals properly

# ─── COLORS & SETTINGS ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set +e 

# Trap Ctrl+C (SIGINT) so it doesn't kill the menu loop
trap '' SIGINT 

# ─── UI COMPONENTS ──────────────────────────────────────────────

show_header() {
    clear
    echo -e "${CYAN}🛰️  OVERLORD SYSTEM MANAGER${NC}"
    echo -e "${BLUE}=========================${NC}"
}

# Standardized input function to prevent looping
pause_and_return() {
    echo -e "\n${BLUE}-------------------------${NC}"
    read -p "Press [Enter] to return to menu..." dummy
}

# ─── MODULES ────────────────────────────────────────────────────

install_daemon() {
    local mode=$1 
    show_header
    echo -e "${YELLOW}📦 Mode: ${mode^^} INSTALLATION${NC}"
    
    if [ "$mode" == "full" ]; then
        if [ -z "$DEPLOY_TOKEN" ] || [ -z "$CONVEX_URL" ]; then
            echo -e "${RED}❌ Missing DEPLOY_TOKEN or CONVEX_URL.${NC}"
            pause_and_return
            return
        fi
        apt-get update -y && apt-get install -y curl sqlite3
    fi

    ARCH=$(uname -m)
    BINARY_NAME=$([ "$ARCH" == "x86_64" ] && echo "overlord-linux-amd64" || echo "overlord-linux-arm64")
    
    echo -e "🚚 Installing Binary..."
    curl -L "https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0/$BINARY_NAME" -o /usr/local/bin/overlord-daemon
    chmod +x /usr/local/bin/overlord-daemon

    if [ "$mode" == "full" ]; then
        echo -e "⚙️  Configuring Service..."
        mkdir -p /var/lib/overlord
        JWT_SECRET=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 64)
        
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

    systemctl restart overlord-daemon 2>/dev/null
    echo -e "${GREEN}✅ Operation Complete.${NC}"
    sleep 2
}

view_logs() {
    show_header
    echo -e "${YELLOW}📜 LOG VIEWER${NC}"
    echo -e "1) Database  2) API/Web  3) Everything  b) Back"
    read -p "Selection: " log_opt

    case $log_opt in
        1) filter="DB|SQLite|ips|attack_logs" ;;
        2) filter="GIN|API|listening|http" ;;
        3) filter="." ;;
        *) return ;;
    esac

    echo -e "${BLUE}Streaming logs... Press Ctrl+C to stop.${NC}"
    # Temporarily allow SIGINT for journalctl
    trap - SIGINT
    journalctl -u overlord-daemon -f -n 50 | grep -E -i --line-buffered "$filter"
    trap '' SIGINT 
    
    pause_and_return
}

# ─── MAIN MENU LOOP ─────────────────────────────────────────────

while true; do
    show_header
    echo -e "1) Install Overlord (Full)"
    echo -e "2) Update Binary Only"
    echo -e "3) DB Maintenance"
    echo -e "4) View Logs"
    echo -e "5) Self Destruct"
    echo -e "q) Exit"
    echo -e "${BLUE}-------------------------${NC}"
    echo -n -e "${YELLOW}Selection:${NC} "
    read choice

    case $choice in
        1) install_daemon "full" ;;
        2) install_daemon "binary" ;;
        3) 
            show_header
            echo -e "1) Wipe DB  2) Total Purge  b) Back"
            read -p "Action: " db_opt
            if [ "$db_opt" == "1" ]; then
                systemctl stop overlord-daemon
                rm -f /var/lib/overlord/overlord.db*
                systemctl start overlord-daemon
                echo -e "${GREEN}DB Reset.${NC}"
                sleep 1
            fi
            ;;
        4) view_logs ;;
        5) 
            echo -e "${RED}⚠️  Are you sure? (y/n)${NC}"
            read confirm
            if [ "$confirm" == "y" ]; then
                systemctl stop overlord-daemon
                rm -rf /etc/systemd/system/overlord-daemon.service /usr/local/bin/overlord-daemon /var/lib/overlord
                systemctl daemon-reload
                echo -e "${GREEN}Purged.${NC}"; exit 0
            fi
            ;;
        q|Q) clear; exit 0 ;;
        *) 
            # If invalid, show error briefly then the loop will refresh
            echo -e "${RED}Invalid selection.${NC}"
            sleep 1 
            ;;
    esac
done
