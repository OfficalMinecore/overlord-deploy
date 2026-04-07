#!/bin/bash

# Overlord DB Reset Utility
# Wipes local telemetry and re-initializes the database

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Please run as root (or use sudo)${NC}"
  exit 1
fi

echo -e "${CYAN}💾 Overlord Database Reset${NC}"
echo -e "---------------------------"

# 1. Stop Service
echo -e "🛑 Stopping overlord-daemon service..."
systemctl stop overlord-daemon || true

# 2. Identify DB Path
DB_PATH=$(systemctl show overlord-daemon -p Environment | grep -o 'DB_PATH=[^ ]*' | cut -d= -f2 || echo "/var/lib/overlord/overlord.db")

# 3. Delete DB Files
if [ -f "$DB_PATH" ]; then
    echo -e "🗑️  Deleting database at $DB_PATH..."
    rm -f "$DB_PATH"
    rm -f "${DB_PATH}-wal" "${DB_PATH}-shm" || true
    echo -e "${GREEN}✅ Database deleted successfully.${NC}"
else
    echo -e "ℹ️  No database found at $DB_PATH. Skipping deletion."
fi

# 4. Restart Service
echo -e "🚀 Restarting overlord-daemon..."
systemctl start overlord-daemon

# 5. Verification
sleep 2
if systemctl is-active --quiet overlord-daemon; then
    echo -e "${GREEN}✅ System re-initialized. A fresh database is being built.${NC}"
else
    echo -e "${RED}❌ Failed to restart daemon. Check logs with 'journalctl -u overlord-daemon -n 20'${NC}"
fi
