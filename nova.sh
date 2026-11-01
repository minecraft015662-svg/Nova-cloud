#!/usr/bin/env bash
# Nova Cloud installer (Ubuntu / Debian)
# Replace GITHUB_USER with your GitHub username.
GITHUB_USER="YOUR_USERNAME"
REPO="https://github.com/${GITHUB_USER}/nova-cloud.git"
DIR=/opt/nova-cloud
CONF=/etc/nova-cloud

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash nova.sh"; exit 1; }

banner() {
  clear
  echo -e "\e[1;36m"
  echo "  ╔══════════════════════════════════╗"
  echo "  ║            NOVA CLOUD            ║"
  echo "  ╚══════════════════════════════════╝"
  echo -e "\e[0m"
}

install_panel() {
  echo "[1/3] Installing packages..."
  apt-get update -y && apt-get install -y nginx curl git || { echo "Package installation failed"; return; }
  echo "[2/3] Downloading the panel..."
  rm -rf "$DIR"
  git clone --depth 1 "$REPO" "$DIR" || { echo "Repo clone failed. Check GITHUB_USER."; return; }
  echo "[3/3] Nginx setup..."
  cat > /etc/nginx/sites-available/nova-cloud <<EOF
server {
  listen 80 default_server;
  root $DIR/panel;
  index index.html;
  location / { try_files \$uri /index.html; }
}
EOF
  ln -sf /etc/nginx/sites-available/nova-cloud /etc/nginx/sites-enabled/nova-cloud
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl enable --now nginx && systemctl reload nginx
  echo "Done. Panel: http://$(curl -fsS ifconfig.me 2>/dev/null || echo SERVER_IP)"
}

uninstall_panel() {
  read -rp "Remove Nova Cloud completely? (y/N): " a </dev/tty
  [[ $a =~ ^[Yy]$ ]] || { echo "Cancel."; return; }
  rm -f /etc/nginx/sites-enabled/nova-cloud /etc/nginx/sites-available/nova-cloud
  systemctl reload nginx 2>/dev/null || true
  systemctl disable --now nova-node 2>/dev/null || true
  rm -f /etc/systemd/system/nova-node.service
  systemctl daemon-reload
  rm -rf "$DIR" "$CONF"
  echo "Nova Cloud has been removed."
}

node_setup() {
  read -rp "Panel URL (e.g. https://panel.example.com): " URL </dev/tty
  read -rp "Node token: " TOKEN </dev/tty
  [ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "Both URL and token are required."; return; }
  apt-get update -y && apt-get install -y curl docker.io qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils lxcfs || { echo "Package installation failed"; return; }
  systemctl enable --now docker
  systemctl enable --now libvirtd 2>/dev/null || true
  [ -e /dev/kvm ] || echo "Warning: /dev/kvm not found. KVM VPS need hardware virtualization (ask your provider to enable nested virtualization). Docker VPS will still work."
  umask 077
  mkdir -p "$CONF"
  printf 'PANEL_URL=%s\nTOKEN=%s\n' "$URL" "$TOKEN" > "$CONF/node.conf"
  echo "Node ready: Docker, KVM and lxcfs installed, config saved in $CONF/node.conf"
  echo "Note: the node agent is not in this repo yet. It will be installed from here once available."
  echo "Docker VPS that run Pterodactyl need the Sysbox runtime (github.com/nestybox/sysbox)."
}

while true; do
  banner
  echo "  1) Install"
  echo "  2) Uninstall"
  echo "  3) Node setup"
  echo "  0) Exit"
  echo
  read -rp "  Choose an option [0-3]: " c </dev/tty
  echo
  case "$c" in
    1) install_panel ;;
    2) uninstall_panel ;;
    3) node_setup ;;
    0) exit 0 ;;
    *) echo "Invalid option." ;;
  esac
  echo
  read -rp "Press Enter to return to the menu..." _ </dev/tty
done
