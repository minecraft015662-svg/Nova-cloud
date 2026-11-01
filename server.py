#!/usr/bin/env python3
"""Nova Cloud panel backend. Python 3 standard library only.

- serves index.html
- /api/login, /api/logout, /api/state  (admin session cookie)
- /api/agent/heartbeat                 (node agents, Bearer token)
Data is stored in a JSON file (NOVA_DATA).
"""
import hmac
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = os.path.dirname(os.path.abspath(__file__))
PANEL_DIR = os.environ.get("NOVA_PANEL_DIR", BASE)
DATA = os.environ.get("NOVA_DATA", os.path.join(BASE, "data.json"))
PORT = int(os.environ.get("NOVA_PORT", "3000"))
HOST = os.environ.get("NOVA_HOST", "127.0.0.1")
ADMIN_USER = os.environ.get("NOVA_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("NOVA_ADMIN_PASS", "admin")
ONLINE_SECS = 30
SESSION_SECS = 7 * 24 * 3600

lock = threading.Lock()
sessions = {}


def default_state():
    return {
        "users": [{"id": 1, "name": "Admin", "email": "admin", "role": "admin"}],
        "nodes": [],
        "vps": [],
        "nid": 10,
    }


def load_state():
    try:
        with open(DATA, "r", encoding="utf-8") as f:
            d = json.load(f)
        for k, v in default_state().items():
            d.setdefault(k, v)
        return d
    except Exception:
        return default_state()


def save_state():
    os.makedirs(os.path.dirname(os.path.abspath(DATA)), exist_ok=True)
    tmp = DATA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f)
    os.replace(tmp, DATA)


state = load_state()


def view():
    """State as sent to the browser, with live node status."""
    now = time.time()
    out = json.loads(json.dumps(state))
    for n in out["nodes"]:
        seen = n.get("seen")
        if not seen:
            n["status"] = "connecting"
        elif now - seen <= ONLINE_SECS:
            n["status"] = "online"
        else:
            n["status"] = "offline"
    return out


def clean_info(d):
    info = {}
    if not isinstance(d, dict):
        return info
    for k in ("hostname", "cpus", "mem_mb", "disk_gb", "load", "docker", "kvm"):
        v = d.get(k)
        if isinstance(v, (str, int, float, bool)):
            info[k] = v[:80] if isinstance(v, str) else v
    return info


class H(BaseHTTPRequestHandler):
    server_version = "NovaCloud"

    def log_message(self, *a):
        pass

    # helpers
    def send_json(self, code, obj, headers=None):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)

    def body(self, limit=2_000_000):
        n = int(self.headers.get("Content-Length") or 0)
        if n > limit:
            raise ValueError("too large")
        return json.loads(self.rfile.read(n) or b"{}")

    def sid(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "nova_sid":
                return v
        return ""

    def authed(self):
        s = self.sid()
        exp = sessions.get(s)
        if exp and exp > time.time():
            return True
        sessions.pop(s, None)
        return False

    # routes
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/state":
            if not self.authed():
                return self.send_json(401, {"error": "login required"})
            with lock:
                return self.send_json(200, view())
        if path in ("/", "/index.html"):
            try:
                with open(os.path.join(PANEL_DIR, "index.html"), "rb") as f:
                    b = f.read()
            except OSError:
                return self.send_json(500, {"error": "index.html not found"})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(b)
            return
        self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            if path == "/api/login":
                d = self.body(10_000)
                ok_u = hmac.compare_digest(str(d.get("username", "")), ADMIN_USER)
                ok_p = hmac.compare_digest(str(d.get("password", "")), ADMIN_PASS)
                if not (ok_u and ok_p):
                    time.sleep(0.6)
                    return self.send_json(401, {"error": "wrong username or password"})
                s = secrets.token_hex(24)
                sessions[s] = time.time() + SESSION_SECS
                return self.send_json(
                    200, {"ok": True},
                    {"Set-Cookie": "nova_sid=%s; HttpOnly; SameSite=Strict; Path=/; Max-Age=%d" % (s, SESSION_SECS)},
                )
            if path == "/api/logout":
                sessions.pop(self.sid(), None)
                return self.send_json(200, {"ok": True}, {"Set-Cookie": "nova_sid=; Path=/; Max-Age=0"})
            if path == "/api/agent/heartbeat":
                auth = self.headers.get("Authorization", "")
                tok = auth[7:].strip() if auth.startswith("Bearer ") else ""
                d = self.body(20_000)
                with lock:
                    node = None
                    for n in state["nodes"]:
                        if tok and hmac.compare_digest(str(n.get("token", "")), tok):
                            node = n
                            break
                    if not node:
                        return self.send_json(401, {"error": "unknown node token"})
                    node["seen"] = time.time()
                    node["info"] = clean_info(d)
                    save_state()
                return self.send_json(200, {"ok": True, "node": node["name"]})
        except Exception:
            return self.send_json(400, {"error": "bad request"})
        self.send_json(404, {"error": "not found"})

    def do_PUT(self):
        if self.path.split("?")[0] != "/api/state":
            return self.send_json(404, {"error": "not found"})
        if not self.authed():
            return self.send_json(401, {"error": "login required"})
        try:
            d = self.body()
            users, nodes, vps = d["users"], d["nodes"], d["vps"]
            if not all(isinstance(x, list) for x in (users, nodes, vps)):
                raise ValueError
            with lock:
                old = {n["id"]: n for n in state["nodes"]}
                for n in nodes:
                    n.pop("status", None)
                    o = old.get(n.get("id"))
                    if o:  # runtime data belongs to the server
                        n["seen"] = o.get("seen")
                        n["info"] = o.get("info")
                    else:
                        n.pop("seen", None)
                        n.pop("info", None)
                state["users"], state["nodes"], state["vps"] = users, nodes, vps
                state["nid"] = int(d.get("nid", state["nid"]))
                save_state()
            return self.send_json(200, {"ok": True})
        except Exception:
            return self.send_json(400, {"error": "bad request"})


if __name__ == "__main__":
    print("Nova Cloud panel on http://%s:%d (data: %s)" % (HOST, PORT, DATA), flush=True)
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
