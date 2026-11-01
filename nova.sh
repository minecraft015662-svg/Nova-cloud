#!/usr/bin/env bash
# Nova Cloud installer (Ubuntu / Debian)
# Replace GITHUB_USER with your GitHub username.
GITHUB_USER="minecraft015662-svg"
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
  echo "[1/4] Installing packages..."
  apt-get update -y && apt-get install -y nginx curl git || { echo "Package installation failed"; return; }
  echo "[2/4] Downloading the panel..."
  rm -rf "$DIR"
  git clone --depth 1 "$REPO" "$DIR" || { echo "Repo clone failed. Check GITHUB_USER and that the repo is public."; return; }
  # find index.html (works for panel/index.html or index.html in the repo root)
  if [ -f "$DIR/panel/index.html" ]; then ROOT="$DIR/panel"
  elif [ -f "$DIR/index.html" ]; then ROOT="$DIR"
  else echo "index.html not found in the repo."; return; fi
  chmod -R a+rX "$DIR"
  echo "[3/4] Nginx setup (root: $ROOT)..."
  cat > /etc/nginx/sites-available/nova-cloud <<EOF
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name _;
  root $ROOT;
  index index.html;
  location / { try_files \$uri \$uri/ /index.html; }
}
EOF
  ln -sf /etc/nginx/sites-available/nova-cloud /etc/nginx/sites-enabled/nova-cloud
  rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
  nginx -t || { echo "Nginx config test failed"; return; }
  systemctl enable nginx >/dev/null 2>&1
  systemctl restart nginx
  command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active" && ufw allow 80/tcp >/dev/null
  echo "[4/4] Checking the panel..."
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)
  if [ "$code" = "200" ]; then
    echo "Done. Panel: http://$(curl -fsS ifconfig.me 2>/dev/null || echo SERVER_IP)  (login: admin / admin)"
  else
    echo "Panel check failed (HTTP $code). Last nginx errors:"
    tail -n 5 /var/log/nginx/error.log 2>/dev/null
  fi
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
