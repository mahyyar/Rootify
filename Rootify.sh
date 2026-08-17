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

# -----------------------------
# Update server
# -----------------------------

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

# -----------------------------
# Set root password
# -----------------------------

log "Setting root password..."

while true; do

    read -s -p "New root password: " ROOT_PASS1
    echo

    read -s -p "Confirm password: " ROOT_PASS2
    echo

    if [[ "$ROOT_PASS1" == "$ROOT_PASS2" && -n "$ROOT_PASS1" ]]; then
        break
    fi

    echo "Passwords do not match. Try again."

done

echo "root:$ROOT_PASS1" | chpasswd

unset ROOT_PASS1 ROOT_PASS2

log "Root password updated."

# -----------------------------
# SSH configuration
# -----------------------------

SSH_CONF="/etc/ssh/sshd_config"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"

if [[ ! -f "$SSH_CONF" ]]; then
    log "ERROR: sshd_config not found."
    exit 1
fi

log "Configuring SSH..."

# Main config
sed -i -E \
    's/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/' \
    "$SSH_CONF"

sed -i -E \
    's/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' \
    "$SSH_CONF"

# Add settings if they don't exist
grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$SSH_CONF" \
    || echo "PermitRootLogin yes" >> "$SSH_CONF"

grep -qE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$SSH_CONF" \
    || echo "PasswordAuthentication yes" >> "$SSH_CONF"

# -----------------------------
# Fix SSH drop-in overrides
# -----------------------------

if [[ -d "$SSH_DROPIN_DIR" ]]; then

    log "Checking SSH drop-in configurations..."

    while IFS= read -r -d '' FILE; do

        if grep -qE '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$FILE"; then
            sed -i -E \
                's/^[[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' \
                "$FILE"
        fi

        if grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]+' "$FILE"; then
            sed -i -E \
                's/^[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/' \
                "$FILE"
        fi

    done < <(find "$SSH_DROPIN_DIR" -type f \( -name "*.conf" -o -name "*.cfg" \) -print0)

fi

# -----------------------------
# Validate SSH configuration
# -----------------------------

log "Testing SSH configuration..."

if ! sshd -t; then
    log "ERROR: SSH configuration is invalid."
    exit 1
fi

log "SSH configuration is valid."

# -----------------------------
# Restart SSH
# -----------------------------

log "Restarting SSH service..."

if command -v systemctl &>/dev/null; then

    if systemctl restart ssh 2>/dev/null; then
        log "SSH service restarted."

    elif systemctl restart sshd 2>/dev/null; then
        log "SSHD service restarted."

    else
        log "ERROR: Could not restart SSH."
        exit 1
    fi

else

    if service ssh restart 2>/dev/null; then
        log "SSH service restarted."

    elif service sshd restart 2>/dev/null; then
        log "SSHD service restarted."

    else
        log "ERROR: Could not restart SSH."
        exit 1
    fi

fi

# -----------------------------
# Verify effective configuration
# -----------------------------

log "Checking effective SSH configuration..."

ROOT_LOGIN=$(sshd -T | awk '$1=="permitrootlogin" {print $2}')
PASSWORD_LOGIN=$(sshd -T | awk '$1=="passwordauthentication" {print $2}')

echo
echo "--------------------------------"
echo " SSH CONFIGURATION"
echo "--------------------------------"
echo "PermitRootLogin:       $ROOT_LOGIN"
echo "PasswordAuthentication: $PASSWORD_LOGIN"
echo "--------------------------------"
echo

if [[ "$ROOT_LOGIN" != "yes" ]]; then
    log "ERROR: PermitRootLogin is not enabled."
    exit 1
fi

if [[ "$PASSWORD_LOGIN" != "yes" ]]; then
    log "ERROR: PasswordAuthentication is not enabled."
    exit 1
fi

log "Root SSH password login is ENABLED."

# -----------------------------
# Reboot
# -----------------------------

log "Five seconds to reboot the server..."
sleep 5

log "Rebooting..."
reboot
