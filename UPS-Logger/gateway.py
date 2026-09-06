import csv
import json
import logging
import os
import re
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from datetime import datetime, timezone
from pathlib import Path

CONFIG_PATH = Path(os.environ.get("CONFIG_PATH", "/app/config.json"))
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
RUN_ONCE = os.environ.get("RUN_ONCE", "false").lower() in {"1", "true", "yes"}
VERSION = "2.1.1"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

UPS_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
CSV_FIELDS = [
    "timestamp", "ok", "status", "charge_percent", "runtime_seconds",
    "load_percent", "input_voltage", "battery_voltage", "error"
]


def load_config():
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    ups_list = cfg.get("ups") or []
    seen = set()
    for item in ups_list:
        ups_id = str(item.get("id", ""))
        if not UPS_ID_RE.fullmatch(ups_id):
            raise ValueError(f"Invalid UPS id {ups_id!r}; use only A-Z a-z 0-9 . _ - (max 64 chars)")
        if ups_id in seen:
            raise ValueError(f"Duplicate UPS id: {ups_id}")
        seen.add(ups_id)
        if not item.get("name"):
            raise ValueError(f"UPS {ups_id}: name is required")
        if not item.get("host"):
            raise ValueError(f"UPS {ups_id}: host is required")
        item["port"] = int(item.get("port", 3493))
        item["nut_name"] = str(item.get("nut_name", "ups"))
        item["rated_watts"] = int(item.get("rated_watts", 400))
        if not (1 <= item["rated_watts"] <= 20000):
            raise ValueError(f"UPS {ups_id}: rated_watts out of range")

    return cfg


def read_until(sock, end_marker, timeout=5.0):
    sock.settimeout(timeout)
    chunks = []
    while True:
        try:
            data = sock.recv(4096)
        except socket.timeout:
            break
        if not data:
            break
        chunks.append(data)
        if end_marker in b"".join(chunks):
            break
    return b"".join(chunks).decode("utf-8", errors="replace")


def nut_list_vars(host, port, ups_name):
    command = f"LIST VAR {ups_name}\n".encode("utf-8")
    marker = f"END LIST VAR {ups_name}".encode("utf-8")
    with socket.create_connection((host, port), timeout=5) as sock:
        sock.sendall(command)
        raw = read_until(sock, marker)

    values = {}
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("ERR "):
            raise RuntimeError(f"NUT: {line}")
        parts = line.split(" ", 3)
        if len(parts) != 4 or parts[0] != "VAR":
            continue
        key = parts[2]
        val = parts[3].strip()
        if len(val) >= 2 and val[0] == '"' and val[-1] == '"':
            val = val[1:-1]
        values[key] = val.replace(r'\"', '"').replace(r'\\', '\\')

    if not values:
        raise RuntimeError(f"No NUT variables returned from {host}:{port}/{ups_name}")
    return values


def as_int(value, default=0, lo=None, hi=None):
    try:
        result = int(float(value))
    except (TypeError, ValueError):
        result = default
    if lo is not None:
        result = max(lo, result)
    if hi is not None:
        result = min(hi, result)
    return result


def poll_ups(item):
    result = {
        "id": item["id"],
        "name": item["name"],
        "ratedWatts": item["rated_watts"],
        "ok": False,
        "battery": 0,
        "status": "UNKNOWN",
        "runtime": 0,
        "load": 0,
        "input_voltage": None,
        "battery_voltage": None,
        "error": "",
    }
    try:
        v = nut_list_vars(item["host"], item["port"], item["nut_name"])
        result.update({
            "ok": True,
            "battery": as_int(v.get("battery.charge"), 0, 0, 100),
            "status": str(v.get("ups.status", "UNKNOWN")),
            "runtime": as_int(v.get("battery.runtime"), 0, 0, 604800),
            "load": as_int(v.get("ups.load"), 0, 0, 100),
            "input_voltage": v.get("input.voltage"),
            "battery_voltage": v.get("battery.voltage"),
            "error": "",
        })
    except Exception as exc:
        result["error"] = str(exc)[:160]
    return result


def append_csv(result):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / f"{result['id']}.csv"
    new_file = not path.exists() or path.stat().st_size == 0
    with path.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        if new_file:
            writer.writeheader()
        writer.writerow({
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "ok": result["ok"],
            "status": result["status"],
            "charge_percent": result["battery"],
            "runtime_seconds": result["runtime"],
            "load_percent": result["load"],
            "input_voltage": result["input_voltage"] or "",
            "battery_voltage": result["battery_voltage"] or "",
            "error": result["error"],
        })


def write_latest_json(results):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "ok": True,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "gateway_version": VERSION,
        "ups": results,
    }
    target = DATA_DIR / "latest.json"
    temporary = DATA_DIR / "latest.json.tmp"
    temporary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    temporary.replace(target)


class LocalApiHandler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._send_json(200, {"ok": True, "version": VERSION})
            return
        if path != "/api/ups/latest":
            self._send_json(404, {"ok": False, "error": "not_found"})
            return
        latest_path = DATA_DIR / "latest.json"
        if not latest_path.exists():
            self._send_json(503, {"ok": False, "error": "data_waiting", "ups": []})
            return
        try:
            payload = json.loads(latest_path.read_text(encoding="utf-8-sig"))
            payload["ok"] = True
            payload["gateway_version"] = VERSION
            self._send_json(200, payload)
        except Exception as exc:
            logging.exception("Local API latest.json read failed: %s", exc)
            self._send_json(500, {"ok": False, "error": "latest_json_error"})

    def log_message(self, fmt, *args):
        logging.debug("Local API: " + fmt, *args)


def start_local_api():
    host = os.environ.get("LOCAL_API_HOST", "0.0.0.0").strip() or "0.0.0.0"
    port = int(os.environ.get("LOCAL_API_PORT", "8766"))
    server = ThreadingHTTPServer((host, port), LocalApiHandler)
    Thread(target=server.serve_forever, name="eaton-ups-local-api", daemon=True).start()
    logging.info("Local Edge API started: http://%s:%d/api/ups/latest", host, port)
    return server


def run_cycle(cfg):
    results = []
    for item in cfg.get("ups", []):
        result = poll_ups(item)
        append_csv(result)
        results.append(result)
        if result["ok"]:
            logging.info(
                "UPS %s status=%s battery=%s%% runtime=%ss load=%s%%",
                result["id"], result["status"], result["battery"], result["runtime"], result["load"]
            )
        else:
            logging.error("UPS %s read failed: %s", result["id"], result["error"])

    write_latest_json(results)


def main():
    start_local_api()
    cfg = load_config()
    interval = max(10, int((cfg.get("logger") or {}).get("poll_seconds", 60)))
    logging.info("Eaton UPS Gateway v%s started: %d UPS(s), interval=%ss", VERSION, len(cfg.get("ups", [])), interval)
    while True:
        try:
            cfg = load_config()
            run_cycle(cfg)
            interval = max(10, int((cfg.get("logger") or {}).get("poll_seconds", 60)))
        except Exception as exc:
            logging.exception("Gateway cycle failed: %s", exc)
        if RUN_ONCE:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
