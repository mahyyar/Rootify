#!/usr/bin/env bash

set -euo pipefail
clear

COLOR="\033[38;5;46m"
RESET="\033[0m"

log() {
    echo -e "${COLOR}[ INFO ] $*${RESET}"
}

if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root: sudo bash <script>"
    exit 1
fi

log "Script started."

read -p "Do you want to update the server? (y/n): " UPDATE_ANSWER

if [[ "$UPDATE_ANSWER" =~ ^[Yy]$ ]]; then
    if command -v apt-get &>/dev/null; then
        log "Updating system (apt-get)..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
        log "System update completed."
    elif command -v yum &>/dev/null; then
        log "Updating system (yum)..."
        yum update -y
        log "System update completed."
    else
        log "Unknown package manager. Skipping update."
    fi
else
    log "Skipping system update."
fi

log "Setting root password..."

while true; do
    read -s -p "New root password: " ROOT_PASS1
    echo
    read -s -p "Confirm password: " ROOT_PASS2
    echo

    if [[ "$ROOT_PASS1" == "$ROOT_PASS2" && -n "$ROOT_PASS1" ]]; then
        break
    else
        echo "Passwords do not match. Try again."
    fi
done

echo "root:$ROOT_PASS1" | chpasswd
unset ROOT_PASS1 ROOT_PASS2

log "Root password updated."

SSH_CONF="/etc/ssh/sshd_config"

if [[ ! -f "$SSH_CONF" ]]; then
    log "ERROR: sshd_config not found."
    exit 1
fi

log "Modifying SSH configuration..."

if grep -qE '^\s*PermitRootLogin' "$SSH_CONF"; then
    sed -i -E 's/^\s*PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONF"
else
    echo "PermitRootLogin yes" >> "$SSH_CONF"
fi

if grep -qE '^\s*PasswordAuthentication' "$SSH_CONF"; then
    sed -i -E 's/^\s*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONF"
else
    echo "PasswordAuthentication yes" >> "$SSH_CONF"
fi

log "Restarting SSH service..."

if command -v systemctl &>/dev/null; then
    if systemctl list-unit-files | grep -q sshd; then
        systemctl restart sshd
    elif systemctl list-unit-files | grep -q ssh; then
        systemctl restart ssh
    else
        service ssh restart  service sshd restart  log "SSH restart failed."
    fi
else
    service ssh restart  service sshd restart  log "SSH restart failed."
fi

log "SSH restarted."

log "Five seconds to reboot the server"
sleep 5

log "Rebooting..."
reboot
