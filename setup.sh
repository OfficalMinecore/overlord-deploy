#!/bin/bash

# Overlord Management Utility
# Unified tool for Installation, Maintenance, and Decommissioning
# Compatible with: Proxmox (Debian), Ubuntu, Debian

# Colors for pretty logs
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

## Security & Environment
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set +e

# --- FUNCTIONS ──────────────────────────────────────────────────

show_header() {
    clear
    echo -e "${CYAN}🛰️  OVERLORD SYSTEM MANAGER${NC}"
    echo -e "${BLUE}=========================${NC}"
}

# Helper for robust input
get_input() {
    local prompt=$1
    local var_name=$2
    printf "${YELLOW}${prompt}${NC} "
    read -r "$var_name"
}

install_daemon() {
    local mode=$1 
    show_header
    echo -e "${YELLOW}📦 Mode: ${mode^^} INSTALLATION${NC}"
    
    if [ "$mode" == "full" ]; then
        if [ -z "$DEPLOY_TOKEN" ] || [ -z "$CONVEX_URL" ]; then
            echo -e "${RED}❌ ERROR: Environment variables DEPLOY_TOKEN and CONVEX_URL are required.${NC}"
            echo -e "Usage: DEPLOY_TOKEN=xxx CONVEX_URL=yyy $0"
            get_input "Press enter to return..." dummy
            return
        fi

        echo -e "🔍 Checking system dependencies..."
        apt-get update -y && apt-get install -y curl sqlite3
    fi

    # Binary Selection
    ARCH=$(uname -m)
    BASE_URL="https://github.com/OfficalMinecore/overlord-deploy/releases/download/v1.0.0"
    
    if [ "$ARCH" == "x86_64" ]; then
        BINARY_NAME="overlord-linux-amd64"
    else
        BINARY_NAME="overlord-linux-arm64"
    fi
    BINARY_URL="${BASE_URL}/${BINARY_NAME}"

    echo -e "🚚 Installing Binary..."
    if [ -f "./${BINARY_NAME}" ]; then
        echo -e "${GREEN}✨ Using local binary: ${BINARY_NAME}${NC}"
        cp "./${BINARY_NAME}" /usr/local/bin/overlord-daemon
    else
        echo -e "🌐 Downloading from GitHub..."
        curl -L "$BINARY_URL" -o /usr/local/bin/overlord-daemon
    fi
    
    chmod +x /usr/local/bin/overlord-daemon

    if [ "$mode" == "full" ]; then
        echo -e "⚙️  Configuring Service..."
        mkdir -p /var/lib/overlord
        
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

    if [ -f "/etc/systemd/system/overlord-daemon.service" ]; then
        echo -e "🚀 Starting Overlord..."
        systemctl restart overlord-daemon
        echo -e "${GREEN}✅ Done!${NC}"
    else
        echo -e "${YELLOW}⚠️ Binary updated, but no service found. Run Full Install to activate.${NC}"
    fi
    sleep 2
}

db_maintenance() {
    show_header
    echo -e "${YELLOW}💾 DB MAINTENANCE${NC}"
    echo -e "1) Reinstall DB (Wipe and Refresh)"
    echo -e "2) Delete Everything Related to DB"
    echo -e "b) Back"
    get_input "Selection:" db_opt

    case $db_opt in
        1)
            systemctl stop overlord-daemon 2>/dev/null
            rm -f /var/lib/overlord/overlord.db*
            systemctl start overlord-daemon 2>/dev/null
            echo -e "${GREEN}✅ Database reset complete.${NC}"
            ;;
        2)
            systemctl stop overlord-daemon 2>/dev/null
            rm -rf /var/lib/overlord/*.db*
            echo -e "${GREEN}✅ All database files removed.${NC}"
            ;;
        *) return ;;
    esac
    get_input "Press enter to return..." dummy
}

self_destruct() {
    show_header
    echo -e "${RED}☢️ SELF DESTRUCT MENU${NC}"
    echo -e "1) Instant Self Destruct"
    echo -e "2) Timed Self Destruct"
    echo -e "b) Back"
    get_input "Selection:" sd_opt

    if [ "$sd_opt" == "2" ]; then
        get_input "Enter delay in seconds:" delay
        [[ $delay =~ ^[0-9]+$ ]] || { echo "Invalid number"; sleep 1; return; }
        echo -e "${YELLOW}⏳ Self-destruct armed. T-minus $delay seconds...${NC}"
        sleep $delay
    elif [ "$sd_opt" != "1" ]; then
        return
    fi

    echo -e "${RED}🔥🔥 DESTROYING SYSTEM...${NC}"
    systemctl stop overlord-daemon 2>/dev/null
    systemctl disable overlord-daemon 2>/dev/null
    rm -f /etc/systemd/system/overlord-daemon.service
    rm -f /usr/local/bin/overlord-daemon
    rm -rf /var/lib/overlord
    systemctl daemon-reload
    echo -e "${GREEN}💀 Purge complete.${NC}"
    exit 0
}

view_logs() {
    show_header
    echo -e "${YELLOW}📜 LOG VIEWER SELECTION${NC}"
    echo -e "1) DB Logs"
    echo -e "2) Web Service Logs"
    echo -e "3) All Logs"
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
    echo -e "${YELLOW}📜 VIEWING: ${filter}${NC}"
    echo -e "Press [Ctrl+C] once to stop viewing logs and return to menu."
    echo -e "${BLUE}---------------------------------------${NC}"
    
    # Run log viewer in foreground. Ctrl+C will kill journalctl but continue the script
    # because we are NOT calling set -e.
    journalctl -u overlord-daemon -f -n 50 | grep -E -i --line-buffered "$filter"
    
    echo -e "\n${GREEN}Returning to menu...${NC}"
    sleep 1
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
    get_input "Selection:" choice

    case $choice in
        1)
            show_header
            echo -e "a) Detailed Installation (Full)"
            echo -e "b) Only Binary Installation (Update)"
            echo -e "back) Go Back"
            get_input "Mode:" inst_choice
            if [ "$inst_choice" == "a" ]; then install_daemon "full"; 
            elif [ "$inst_choice" == "b" ]; then install_daemon "binary"; fi
            ;;
        2) db_maintenance ;;
        3) self_destruct ;;
        4) view_logs ;;
        q) exit 0 ;;
        *) [ -n "$choice" ] && echo -e "${RED}Invalid selection: $choice${NC}" && sleep 1 ;;
    esac
done
"; 
            elif [ "$inst_choice" == "b" ]; then install_daemon "binary"; fi
            ;;
        2) db_maintenance ;;
        3) self_destruct ;;
        4) view_logs ;;
        q) exit 0 ;;
        *) echo -e "${RED}Invalid selection${NC}"; sleep 1 ;;
    esac
done
