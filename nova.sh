#!/usr/bin/env bash
# Nova Cloud installer (Ubuntu / Debian)
GITHUB_USER="minecraft015662-svg"
REPO="https://github.com/${GITHUB_USER}/Nova-cloud.git"
DIR=/opt/nova-cloud
CONF=/etc/nova-cloud
DATA=/var/lib/nova-cloud

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
  echo "[1/5] Installing packages..."
  apt-get update -y && apt-get install -y nginx curl git python3 || { echo "Package installation failed"; return; }
  echo "[2/5] Downloading the panel..."
  rm -rf "$DIR"
  git clone --depth 1 "$REPO" "$DIR" || { echo "Repo clone failed. Check GITHUB_USER and that the repo is public."; return; }
  SRV=$(find "$DIR" -name server.py -not -path '*/.git/*' | head -n1)
  [ -n "$SRV" ] || { echo "panel/server.py not found in the repo. Upload the whole 'panel' folder (index.html + server.py)."; return; }
  PDIR=$(dirname "$SRV")
  [ -f "$PDIR/index.html" ] || { echo "index.html not found next to server.py ($PDIR)."; return; }
  chmod -R a+rX "$DIR"
  echo "[3/5] Starting the panel service..."
  mkdir -p "$CONF" "$DATA"
  if [ ! -f "$CONF/panel.env" ]; then
    printf 'NOVA_ADMIN_USER=admin\nNOVA_ADMIN_PASS=admin\n' > "$CONF/panel.env"
    chmod 600 "$CONF/panel.env"
  fi
  cat > /etc/systemd/system/nova-panel.service <<EOF
[Unit]
Description=Nova Cloud panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SRV
Environment=NOVA_PANEL_DIR=$PDIR
Environment=NOVA_DATA=$DATA/data.json
EnvironmentFile=-$CONF/panel.env
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable nova-panel >/dev/null 2>&1
  systemctl restart nova-panel
  echo "[4/5] Nginx setup..."
  cat > /etc/nginx/sites-available/nova-cloud <<'EOF'
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name _;
  client_max_body_size 2m;
  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
EOF
  ln -sf /etc/nginx/sites-available/nova-cloud /etc/nginx/sites-enabled/nova-cloud
  rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
  nginx -t || { echo "Nginx config test failed"; return; }
  systemctl enable nginx >/dev/null 2>&1
  systemctl restart nginx
  command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active" && ufw allow 80/tcp >/dev/null
  echo "[5/5] Checking the panel..."
  sleep 2
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)
  if [ "$code" = "200" ]; then
    echo "Done. Panel: http://$(curl -fsS ifconfig.me 2>/dev/null || echo SERVER_IP)  (login: admin / admin)"
    echo "Change the login: edit $CONF/panel.env then run: systemctl restart nova-panel"
  else
    echo "Panel check failed (HTTP $code). Logs:"
    journalctl -u nova-panel -n 8 --no-pager 2>/dev/null
    tail -n 5 /var/log/nginx/error.log 2>/dev/null
  fi
}

uninstall_panel() {
  read -rp "Remove Nova Cloud completely? (y/N): " a </dev/tty
  [[ $a =~ ^[Yy]$ ]] || { echo "Cancel."; return; }
  systemctl disable --now nova-panel 2>/dev/null || true
  systemctl disable --now nova-node 2>/dev/null || true
  rm -f /etc/systemd/system/nova-panel.service /etc/systemd/system/nova-node.service /usr/local/bin/nova-agent
  rm -f /etc/nginx/sites-enabled/nova-cloud /etc/nginx/sites-available/nova-cloud
  systemctl reload nginx 2>/dev/null || true
  systemctl daemon-reload
  rm -rf "$DIR" "$CONF" "$DATA"
  echo "Nova Cloud has been removed."
}

node_setup() {
  read -rp "Panel URL (e.g. http://1.2.3.4): " URL </dev/tty
  read -rp "Node token: " TOKEN </dev/tty
  URL="${URL%/}"
  [ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "Both URL and token are required."; return; }
  apt-get update -y && apt-get install -y curl docker.io qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils lxcfs || { echo "Package installation failed"; return; }
  systemctl enable --now docker
  systemctl enable --now libvirtd 2>/dev/null || true
  [ -e /dev/kvm ] || echo "Warning: /dev/kvm not found. KVM VPS need hardware virtualization (ask your provider to enable nested virtualization). Docker VPS will still work."
  umask 077
  mkdir -p "$CONF"
  printf 'PANEL_URL=%s\nTOKEN=%s\n' "$URL" "$TOKEN" > "$CONF/node.conf"
  umask 022

  cat > /usr/local/bin/nova-agent <<'AGENT'
#!/usr/bin/env bash
# Nova Cloud node agent: tells the panel this node is alive, every 10 seconds.
. /etc/nova-cloud/node.conf
while true; do
  cpus=$(nproc)
  mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  disk=$(df -BG --output=size / | tail -n1 | tr -dc 0-9)
  load=$(cut -d' ' -f1 /proc/loadavg)
  docker=false; command -v docker >/dev/null 2>&1 && docker=true
  kvm=false; [ -e /dev/kvm ] && kvm=true
  curl -fsS -m 8 -X POST "$PANEL_URL/api/agent/heartbeat" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"hostname\":\"$(hostname)\",\"cpus\":$cpus,\"mem_mb\":$mem,\"disk_gb\":${disk:-0},\"load\":$load,\"docker\":$docker,\"kvm\":$kvm}" \
    >/dev/null 2>&1
  sleep 10
done
AGENT
  chmod +x /usr/local/bin/nova-agent
  cat > /etc/systemd/system/nova-node.service <<'EOF'
[Unit]
Description=Nova Cloud node agent
After=network-online.target

[Service]
ExecStart=/usr/local/bin/nova-agent
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable nova-node >/dev/null 2>&1
  systemctl restart nova-node

  code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 -X POST "$URL/api/agent/heartbeat" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}')
  case "$code" in
    200) echo "Node connected to the panel. It shows 'online' within a few seconds." ;;
    401) echo "The panel rejected the token. Copy the token again from Admin panel > Nodes." ;;
    000) echo "Cannot reach $URL. Check the panel URL, firewall and that the panel is running." ;;
    *)   echo "Unexpected answer from the panel (HTTP $code)." ;;
  esac
  echo "Agent service: systemctl status nova-node"
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
