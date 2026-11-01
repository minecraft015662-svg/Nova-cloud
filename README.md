# Nova Cloud

Your own hosting control panel (vPanel).

## Repo structure (upload exactly like this)

```
Nova-cloud/
├── README.md
├── nova.sh
└── panel/
    ├── index.html     # panel UI
    └── server.py      # panel backend (Python 3, no extra packages)
```

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/minecraft015662-svg/Nova-cloud/main/nova.sh -o nova.sh
sudo bash nova.sh
```

Menu:

1. Install: installs nginx + python3, starts the `nova-panel` service, checks the panel
2. Uninstall: removes everything
3. Node setup: installs Docker, KVM, lxcfs and the node agent (`nova-node` service)

Login: `admin` / `admin`. Change it in `/etc/nova-cloud/panel.env`, then `systemctl restart nova-panel`.

## Connect a node

1. Panel: Admin panel > Nodes > Create New. The token appears in the list.
2. On the node VPS: `sudo bash nova.sh`, choose 3, enter the panel URL (e.g. `http://1.2.3.4`) and the token.
3. The node shows `online` within seconds. It goes `offline` if the agent stops for 30 seconds.

## Status

- Users, nodes and VPS are saved on the server (`/var/lib/nova-cloud/data.json`).
- Nodes connect for real (agent heartbeat with token).
- Creating real Docker/KVM VPS on a node is the next step. The VPS list is still only a record.
- The panel runs over plain HTTP. Put it behind HTTPS before using real passwords.
