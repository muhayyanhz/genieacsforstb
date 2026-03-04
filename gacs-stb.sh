#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

spinner() {
    local pid=$1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        printf "${CYAN} [%c] ${NC}" "$spinstr"
        spinstr=${spinstr#?}${spinstr%${spinstr#?}}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
}

run_command() {
    local cmd="$1"
    local msg="$2"

    printf "${YELLOW}%-55s${NC}" "$msg..."
    bash -c "$cmd" > /dev/null 2>&1 &
    spinner $!
    wait $!

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Done${NC}"
    else
        echo -e "${RED}Failed${NC}"
        exit 1
    fi
}

print_banner() {

HOSTNAME=$(hostname)
IPADDR=$(hostname -I | awk '{print $1}')
OS=$(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)
KERNEL=$(uname -r)
CPU=$(lscpu | grep "Model name" | sed 's/Model name:\s*//')
RAM=$(free -h | awk '/Mem:/ {print $2}')

echo -e "${BLUE}${BOLD}"
echo "   ___   _   ___ ___     _       _         ___         _        _ _ "
echo "  / __| /_\ / __/ __|   /_\ _  _| |_ ___  |_ _|_ _  __| |_ __ _| | |"
echo " | (_ |/ _ \ (__\__ \  / _ \ || |  _/ _ \  | || ' \(_-<  _/ _\` | | |"
echo "  \___/_/ \_\___|___/ /_/ \_\_,_|\__\___/ |___|_||_/__/\__\__,_|_|_|"
echo ""
echo "                     --- Linux ---"
echo "                     --- Hayyan ---"
echo ""

echo -e "${CYAN}System Information${NC}"
echo "--------------------------------------------------"
echo " Hostname : $HOSTNAME"
echo " IP Addr  : $IPADDR"
echo " OS       : $OS"
echo " Kernel   : $KERNEL"
echo " CPU      : $CPU"
echo " RAM      : $RAM"
echo "--------------------------------------------------"
echo -e "${NC}"
}

if [ "$EUID" -ne 0 ]; then
 echo "Run script as root"
 exit
fi

print_banner

total_steps=16
current_step=0

echo -e "\n${MAGENTA}${BOLD}Starting GenieACS Installation${NC}\n"

run_command "apt update -y" "Updating system ($(( ++current_step ))/$total_steps)"

run_command "apt install -y curl gnupg build-essential logrotate lsb-release" "Installing base packages ($(( ++current_step ))/$total_steps)"

# Swap
if ! swapon --show | grep -q swap; then
run_command "fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab" "Creating swap memory ($(( ++current_step ))/$total_steps)"
else
current_step=$((current_step+1))
fi

# NodeJS
run_command "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -" "Adding NodeJS repo ($(( ++current_step ))/$total_steps)"

run_command "apt install -y nodejs" "Installing NodeJS ($(( ++current_step ))/$total_steps)"

# MongoDB Repo
run_command "curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg" "Adding MongoDB key ($(( ++current_step ))/$total_steps)"

run_command "echo 'deb [ arch=arm64 signed-by=/usr/share/keyrings/mongodb.gpg ] https://repo.mongodb.org/apt/debian bullseye/mongodb-org/4.4 main' > /etc/apt/sources.list.d/mongodb-org.list" "Adding MongoDB repo ($(( ++current_step ))/$total_steps)"

run_command "apt update -y" "Updating repo ($(( ++current_step ))/$total_steps)"

run_command "apt install -y mongodb-org || apt install -y mongodb" "Installing MongoDB ($(( ++current_step ))/$total_steps)"

run_command "systemctl enable mongod || systemctl enable mongodb" "Enabling MongoDB ($(( ++current_step ))/$total_steps)"

run_command "systemctl start mongod || systemctl start mongodb" "Starting MongoDB ($(( ++current_step ))/$total_steps)"

# Install GenieACS
run_command "npm install -g genieacs@1.2.13" "Installing GenieACS ($(( ++current_step ))/$total_steps)"

run_command "useradd --system --no-create-home --user-group genieacs || true" "Creating genieacs user ($(( ++current_step ))/$total_steps)"

run_command "mkdir -p /opt/genieacs/ext /var/log/genieacs" "Creating directories ($(( ++current_step ))/$total_steps)"

run_command "chown -R genieacs:genieacs /opt/genieacs /var/log/genieacs" "Setting permissions ($(( ++current_step ))/$total_steps)"

cat <<EOF > /opt/genieacs/genieacs.env
GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/cwmp.log
GENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/nbi.log
GENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/fs.log
GENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/ui.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/debug.yaml
GENIEACS_EXT_DIR=/opt/genieacs/ext
NODE_OPTIONS=--max-old-space-size=256
EOF

node -e "console.log('GENIEACS_UI_JWT_SECRET=' + require('crypto').randomBytes(128).toString('hex'))" >> /opt/genieacs/genieacs.env

chmod 600 /opt/genieacs/genieacs.env
chown genieacs:genieacs /opt/genieacs/genieacs.env

for service in cwmp nbi fs ui
do
cat <<EOF > /etc/systemd/system/genieacs-$service.service
[Unit]
Description=GenieACS $service
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-$service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload

for service in cwmp nbi fs ui
do
systemctl enable genieacs-$service
systemctl start genieacs-$service
done

cat <<EOF > /etc/logrotate.d/genieacs
/var/log/genieacs/*.log {
 daily
 rotate 7
 compress
 missingok
 notifempty
}
EOF

echo -e "\n${MAGENTA}${BOLD}Service Status${NC}"

for service in mongod mongodb genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui
do
status=$(systemctl is-active $service 2>/dev/null)

if [ "$status" = "active" ]; then
echo -e "${GREEN}✔ $service running${NC}"
fi
done

echo -e "\n${GREEN}${BOLD}GenieACS installation completed!${NC}"
echo -e "${CYAN}Access UI: http://SERVER-IP:3000${NC}"
