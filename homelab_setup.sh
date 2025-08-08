#!/usr/bin/env bash

# homelab_setup.sh
# Usage: sudo bash homelab_setup.sh <username> <ip_range>
# Example: sudo bash homelab-setup.sh alice 10.0.0.0/8

set -euo pipefail

# Global vars
TOTAL_STEPS=7
CURRENT_STEP=0

# Print usage
usage() {
  cat <<EOF
Usage: sudo bash $0 <username> <ip_range>
  <username>  — non-root user to create/configure
  <ip_range>  — CIDR block (e.g. 10.0.0.0/8) allowed for SSH
EOF
  exit 1
}

# Advance progress bar
progress() {
  (( CURRENT_STEP++ ))
  local percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
  local filled=$(( percent / 5 ))
  local empty=$(( 20 - filled ))
  printf "\r[%-${filled}s%${empty}s] %3d%% - %s" \
    "$(printf '#%.0s' $(seq 1 $filled))" "" "$percent" "$1"
  if [[ $CURRENT_STEP -eq $TOTAL_STEPS ]]; then
    printf "\n"
  fi
}

# 1. Validate environment
validate() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root." >&2; exit 1
  fi
  if [[ $# -ne 2 ]]; then
    usage
  fi
  USERNAME=$1
  IP_RANGE=$2
  SUDOERS_FILE="/etc/sudoers.d/${USERNAME}"
  NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
  SSH_CONFIG="/etc/ssh/sshd_config"
  progress "Validated parameters"
}

# 2. Create user and add to sudo
setup_user() {
  if ! id "$USERNAME" &>/dev/null; then
    adduser --gecos "" --disabled-password "$USERNAME"
  fi
  usermod -aG sudo "$USERNAME"
  progress "User $USERNAME created/updated"
}

# 3. Configure passwordless sudo
configure_sudo() {
  cat > "$SUDOERS_FILE" <<EOF
${USERNAME} ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 0440 "$SUDOERS_FILE"
  chown root:root "$SUDOERS_FILE"
  progress "Passwordless sudo configured"
}

# 4. Allow user to paste SSH public key
configure_ssh_key() {
  echo
  echo "Step 4: Paste the SSH public key for user '$USERNAME' and press Ctrl+D:"
  mkdir -p /home/"$USERNAME"/.ssh
  chmod 700 /home/"$USERNAME"/.ssh
  cat > /home/"$USERNAME"/.ssh/authorized_keys
  chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
  chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh
  progress "SSH public key installed"
}

# 5. Configure UFW rules
configure_ufw() {
  ufw allow from "${IP_RANGE}" to any port 22 proto tcp
  ufw deny 22/tcp
  ufw --force enable
  progress "UFW rules set"
}

# 6. Harden SSH
harden_ssh() {
  cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
  sed -i -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
         -e 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
         -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
         "$SSH_CONFIG"
  # Restrict to user and source prefix
  grep -q "^AllowUsers" "$SSH_CONFIG" && \
    sed -i "s|^AllowUsers.*|AllowUsers ${USERNAME}@${IP_RANGE%%/*}|g" "$SSH_CONFIG" || \
    echo "AllowUsers ${USERNAME}@${IP_RANGE%%/*}" >> "$SSH_CONFIG"
  systemctl restart ssh
  progress "SSH hardened"
}

# 7. Update & install essentials
install_packages() {
  apt update
  apt -y upgrade
  apt -y install vim htop curl git
  progress "Essential packages installed"
}

# 8. Configure Netplan DHCP
configure_netplan() {
  PRIMARY_IFACE=$(ip -o link show | awk -F': ' '/enp|eth/ {print $2; exit}')
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${PRIMARY_IFACE}:
      dhcp4: true
EOF
  netplan apply
  progress "Netplan configured"
}

# Main
main() {
  validate "$@"
  setup_user
  configure_sudo
  configure_ssh_key
  configure_ufw
  harden_ssh
  install_packages
  configure_netplan
  echo "=== Homelab setup complete for user $USERNAME ==="
}

main "$@"
