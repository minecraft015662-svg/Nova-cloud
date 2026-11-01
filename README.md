# Nova Cloud

Your own hosting control panel (vPanel).

## Repo structure

```
nova-cloud/
├── README.md
├── nova.sh          # installer menu
└── panel/
    └── index.html   # panel UI
```

## Setup

1. Create a GitHub repo named `nova-cloud` and upload all three files in this structure.
2. In `nova.sh`, replace `GITHUB_USER="YOUR_USERNAME"` with your GitHub username.

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/nova-cloud/main/nova.sh -o nova.sh
sudo bash nova.sh
```

Menu:

1. Install: installs nginx and serves the panel
2. Uninstall: removes the panel and its config
3. Node setup: installs Docker, KVM (libvirt) and lxcfs, and saves the node config on a new VPS

Works on Ubuntu and Debian.

## Status

- The panel UI is a demo. Users, nodes and VPS are simulated in the browser.
- The node agent and the real backend are the next step.
