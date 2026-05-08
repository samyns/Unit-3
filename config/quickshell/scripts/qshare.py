#!/usr/bin/env python3
"""
qshare — partage de fichiers PC <-> téléphone via HTTP + QR code

Usage CLI :
    qshare send <fichier|dossier...> [--tunnel] [-k] [-o IGNORED]
    qshare recv [-o DIR] [--tunnel] [-k]

Usage interne (depuis Quickshell) :
    qshare ... --qr-out /tmp/qshare-qr.png --event-file /tmp/qshare-events
"""
from __future__ import annotations

import argparse
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, unquote

try:
    import qrcode
    from qrcode.image.pil import PilImage
except ImportError:
    sys.exit("Manque la dépendance : pacman -S python-qrcode  (ou pip install qrcode[pil])")


NIER_BG, NIER_FG, NIER_ACCENT, NIER_DIM = "#1c1a17", "#a89a7e", "#d4c8a8", "#6b6453"
ANSI_FG = "\033[38;2;168;154;126m"
ANSI_DIM = "\033[38;2;107;100;83m"
ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"


# ─── Réseau ───────────────────────────────────────────────────────────────────
def get_local_ip(iface: str | None = None) -> str:
    if iface:
        try:
            import fcntl, struct
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                packed = struct.pack("256s", iface.encode()[:15])
                return socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, packed)[20:24])
        except OSError as e:
            sys.exit(f"Impossible de lire l'IP de {iface}: {e}")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("", 0))
        return s.getsockname()[1]


# ─── Cloudflare Tunnel ────────────────────────────────────────────────────────
def start_cloudflared(local_port: int) -> tuple[subprocess.Popen, str]:
    if not shutil.which("cloudflared"):
        sys.exit("cloudflared introuvable. Installe-le : pacman -S cloudflared")

    cmd = [
        "cloudflared", "tunnel",
        "--url", f"http://localhost:{local_port}",
        "--protocol", "http2",
        "--edge-ip-version", "4",
        "--no-autoupdate",
    ]
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    url_pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
    public_url: str | None = None
    registered = False
    deadline = time.monotonic() + 30

    print(f"{ANSI_DIM}Démarrage du tunnel Cloudflare…{ANSI_RESET}")
    while time.monotonic() < deadline:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                sys.exit("cloudflared s'est arrêté avant d'établir le tunnel.")
            continue
        if not public_url:
            m = url_pattern.search(line)
            if m:
                public_url = m.group(0)
        if "Registered tunnel connection" in line:
            registered = True
        if public_url and registered:
            break

    if not public_url:
        proc.terminate()
        sys.exit("Impossible de récupérer l'URL du tunnel (timeout).")

    def _drain():
        for _ in iter(proc.stdout.readline, ""):
            pass
    threading.Thread(target=_drain, daemon=True).start()
    return proc, public_url


# ─── QR ───────────────────────────────────────────────────────────────────────
def print_qr(url: str) -> None:
    qr = qrcode.QRCode(border=1, error_correction=qrcode.constants.ERROR_CORRECT_L)
    qr.add_data(url)
    qr.make(fit=True)
    qr.print_ascii(invert=True)


def write_qr_png(url: str, path: Path) -> None:
    """Écrit un PNG du QR avec la palette NieR (fond sombre, modules clairs)."""
    qr = qrcode.QRCode(
        border=2,
        box_size=12,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(
        image_factory=PilImage,
        fill_color=NIER_FG,
        back_color=NIER_BG,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# ─── Event file (IPC vers Quickshell) ─────────────────────────────────────────
class EventLog:
    def __init__(self, path: str | None):
        self.path = Path(path) if path else None
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text("")  # reset
        self._lock = threading.Lock()

    def emit(self, line: str) -> None:
        if not self.path:
            return
        with self._lock:
            with self.path.open("a") as f:
                f.write(line.rstrip("\n") + "\n")


# ─── Préparation du payload pour SEND ─────────────────────────────────────────
def build_payload(paths: list[Path]) -> tuple[Path, str, bool]:
    for p in paths:
        if not p.exists():
            sys.exit(f"Introuvable : {p}")

    if len(paths) == 1 and paths[0].is_file():
        return paths[0], paths[0].name, False

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
    tmp.close()
    zip_path = Path(tmp.name)

    if len(paths) == 1 and paths[0].is_dir():
        archive_name = paths[0].name + ".zip"
        root = paths[0]
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in root.rglob("*"):
                if f.is_file():
                    zf.write(f, f.relative_to(root.parent))
    else:
        archive_name = "qshare_bundle.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in paths:
                if p.is_file():
                    zf.write(p, p.name)
                else:
                    for f in p.rglob("*"):
                        if f.is_file():
                            zf.write(f, f.relative_to(p.parent))
    return zip_path, archive_name, True


# ─── Page HTML d'upload (style NieR) ──────────────────────────────────────────
UPLOAD_HTML = """<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>qshare</title>
<style>
  :root {{ --bg:{bg}; --fg:{fg}; --accent:{accent}; --dim:{dim}; }}
  * {{ box-sizing: border-box; }}
  html, body {{ margin:0; padding:0; background:var(--bg); color:var(--fg);
    font-family:'Iosevka','JetBrains Mono',ui-monospace,monospace; min-height:100vh; }}
  main {{ max-width:540px; margin:0 auto; padding:2.5rem 1.5rem; }}
  h1 {{ font-weight:400; letter-spacing:0.4em; text-transform:uppercase;
    border-bottom:1px solid var(--dim); padding-bottom:0.6rem; font-size:1.1rem; }}
  .frame {{ border:1px solid var(--dim); padding:1.5rem; margin-top:1.5rem; position:relative; }}
  .frame::before, .frame::after {{ content:""; position:absolute; width:8px; height:8px;
    border:1px solid var(--accent); background:var(--bg); }}
  .frame::before {{ top:-4px; left:-4px; }}
  .frame::after {{ bottom:-4px; right:-4px; }}
  input[type=file] {{ display:block; width:100%; color:var(--fg); margin-bottom:1.2rem; }}
  button {{ width:100%; background:transparent; color:var(--accent); border:1px solid var(--accent);
    padding:0.7rem; font-family:inherit; letter-spacing:0.3em; text-transform:uppercase;
    cursor:pointer; transition:all 0.2s; }}
  button:hover:not(:disabled) {{ background:var(--accent); color:var(--bg); }}
  button:disabled {{ opacity:0.4; cursor:wait; }}
  .progress {{ margin-top:1rem; height:4px; background:var(--dim); display:none; overflow:hidden; }}
  .progress > div {{ height:100%; width:0%; background:var(--accent); transition:width 0.1s linear; }}
  .status {{ margin-top:1rem; min-height:1.4em; font-size:0.9rem; }}
  .ok {{ color:var(--accent); }}
  .err {{ color:#c97a6f; }}
</style>
</head><body>
<main>
  <h1>qshare // upload</h1>
  <div class="frame">
    <input type="file" id="files" multiple>
    <button id="send">Transmettre</button>
    <div class="progress"><div id="bar"></div></div>
    <div class="status" id="status"></div>
  </div>
</main>
<script>
const TOKEN = "{token}";
const filesInput = document.getElementById("files");
const btn = document.getElementById("send");
const bar = document.getElementById("bar");
const progress = document.querySelector(".progress");
const status = document.getElementById("status");
btn.addEventListener("click", () => {{
  const files = filesInput.files;
  if (!files.length) {{ status.textContent = "Aucun fichier sélectionné."; return; }}
  const fd = new FormData();
  for (const f of files) fd.append("files", f, f.name);
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/upload?t=" + TOKEN);
  xhr.upload.onprogress = e => {{
    if (e.lengthComputable) {{
      progress.style.display = "block";
      bar.style.width = (e.loaded / e.total * 100).toFixed(1) + "%";
    }}
  }};
  xhr.onload = () => {{
    btn.disabled = false;
    if (xhr.status === 200) {{ status.textContent = "✓ Transfert terminé."; status.className = "status ok"; }}
    else {{ status.textContent = "✗ Erreur " + xhr.status; status.className = "status err"; }}
  }};
  xhr.onerror = () => {{ btn.disabled = false; status.textContent = "✗ Erreur réseau."; status.className = "status err"; }};
  btn.disabled = true;
  status.textContent = "Envoi en cours…";
  status.className = "status";
  xhr.send(fd);
}});
</script>
</body></html>
"""


# ─── Handlers HTTP ────────────────────────────────────────────────────────────
class SendHandler(BaseHTTPRequestHandler):
    file_path: Path = None  # type: ignore[assignment]
    file_name: str = ""
    token: str = ""
    keep_alive: bool = False
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.address_string()}] {fmt % args}{ANSI_RESET}")

    def do_GET(self):  # noqa: N802
        if f"/{self.token}/" not in self.path:
            self.send_error(404); return
        size = self.file_path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{quote(self.file_name)}"')
        self.end_headers()
        with open(self.file_path, "rb") as f:
            shutil.copyfileobj(f, self.wfile)
        print(f"{ANSI_FG}{ANSI_BOLD}✓ {self.file_name} envoyé{ANSI_RESET}")
        if self.events:
            self.events.emit(f"TICK {self.file_name}")
        if not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()


class RecvHandler(BaseHTTPRequestHandler):
    out_dir: Path = None  # type: ignore[assignment]
    token: str = ""
    keep_alive: bool = False
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.address_string()}] {fmt % args}{ANSI_RESET}")

    def do_GET(self):  # noqa: N802
        if self.path != f"/{self.token}":
            self.send_error(404); return
        html = UPLOAD_HTML.format(
            bg=NIER_BG, fg=NIER_FG, accent=NIER_ACCENT, dim=NIER_DIM, token=self.token
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)

    def do_POST(self):  # noqa: N802
        if not self.path.startswith("/upload"):
            self.send_error(404); return
        if f"t={self.token}" not in self.path:
            self.send_error(403); return
        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            self.send_error(400, "multipart/form-data attendu"); return
        boundary = ctype.split("boundary=", 1)[1].encode()
        length = int(self.headers.get("Content-Length", 0))
        saved = self._parse_multipart(boundary, length)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")
        for name in saved:
            print(f"{ANSI_FG}{ANSI_BOLD}✓ reçu : {name}{ANSI_RESET}")
            if self.events:
                self.events.emit(f"TICK {name}")
        if saved and not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()

    def _parse_multipart(self, boundary: bytes, length: int) -> list[str]:
        saved: list[str] = []
        delim = b"--" + boundary
        end_delim = delim + b"--"
        rfile = self.rfile
        remaining = length

        def readline():
            nonlocal remaining
            line = rfile.readline()
            remaining -= len(line)
            return line

        while remaining > 0:
            line = readline()
            if line.startswith(delim):
                break

        while remaining > 0:
            headers: dict[str, str] = {}
            while True:
                line = readline()
                if line in (b"\r\n", b""):
                    break
                k, _, v = line.decode("utf-8", "replace").partition(":")
                headers[k.strip().lower()] = v.strip()
            disp = headers.get("content-disposition", "")
            filename = None
            for piece in disp.split(";"):
                piece = piece.strip()
                if piece.startswith("filename="):
                    filename = unquote(piece.split("=", 1)[1].strip().strip('"'))
            if not filename:
                while remaining > 0:
                    line = readline()
                    if line.startswith(delim):
                        break
                if line.startswith(end_delim):
                    break
                continue
            safe_name = Path(filename).name
            dest = _unique_path(self.out_dir / safe_name)
            with open(dest, "wb") as out:
                prev = b""
                while remaining > 0:
                    line = rfile.readline()
                    remaining -= len(line)
                    if line.startswith(delim):
                        if prev.endswith(b"\r\n"):
                            prev = prev[:-2]
                        out.write(prev)
                        break
                    out.write(prev)
                    prev = line
            saved.append(dest.name)
            if line.startswith(end_delim):
                break
        return saved


def _unique_path(p: Path) -> Path:
    if not p.exists():
        return p
    stem, suf = p.stem, p.suffix
    i = 1
    while True:
        cand = p.with_name(f"{stem} ({i}){suf}")
        if not cand.exists():
            return cand
        i += 1


# ─── Commandes ────────────────────────────────────────────────────────────────
def _start_server_with_port(handler_cls, preferred_port: int):
    port = preferred_port if preferred_port else _free_port()
    try:
        return ThreadingHTTPServer(("0.0.0.0", port), handler_cls), port
    except OSError:
        port = _free_port()
        return ThreadingHTTPServer(("0.0.0.0", port), handler_cls), port


def _emit_ready(events: EventLog, url: str, qr_path: Path | None) -> None:
    events.emit(f"URL {url}")
    if qr_path:
        events.emit(f"QR {qr_path}")
    events.emit("READY")


def cmd_send(args: argparse.Namespace) -> None:
    paths = [Path(p).expanduser().resolve() for p in args.paths]
    served, name, is_tmp = build_payload(paths)
    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)

    SendHandler.file_path = served
    SendHandler.file_name = name
    SendHandler.token = token
    SendHandler.keep_alive = args.keep_alive
    SendHandler.done_event = threading.Event()
    SendHandler.events = events

    preferred = args.port or (8080 if args.tunnel else 0)
    server, port = _start_server_with_port(SendHandler, preferred)

    tunnel_proc = None
    if args.tunnel:
        tunnel_proc, public = start_cloudflared(port)
        url = f"{public}/{token}/{quote(name)}"
    else:
        ip = get_local_ip(args.iface)
        url = f"http://{ip}:{port}/{token}/{quote(name)}"

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    _print_banner("SEND", name, url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    try:
        if args.keep_alive:
            server.serve_forever()
        else:
            t = threading.Thread(target=server.serve_forever, daemon=True)
            t.start()
            SendHandler.done_event.wait()
            server.shutdown()
    except KeyboardInterrupt:
        print(f"\n{ANSI_DIM}interrompu{ANSI_RESET}")
        events.emit("CANCELLED")
    finally:
        if is_tmp:
            try: served.unlink()
            except OSError: pass
        if tunnel_proc:
            tunnel_proc.terminate()


def cmd_recv(args: argparse.Namespace) -> None:
    out = Path(args.output).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)

    RecvHandler.out_dir = out
    RecvHandler.token = token
    RecvHandler.keep_alive = args.keep_alive
    RecvHandler.done_event = threading.Event()
    RecvHandler.events = events

    preferred = args.port or (8080 if args.tunnel else 0)
    server, port = _start_server_with_port(RecvHandler, preferred)

    tunnel_proc = None
    if args.tunnel:
        tunnel_proc, public = start_cloudflared(port)
        url = f"{public}/{token}"
    else:
        ip = get_local_ip(args.iface)
        url = f"http://{ip}:{port}/{token}"

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    _print_banner("RECV", str(out), url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    try:
        if args.keep_alive:
            server.serve_forever()
        else:
            t = threading.Thread(target=server.serve_forever, daemon=True)
            t.start()
            RecvHandler.done_event.wait()
            server.shutdown()
    except KeyboardInterrupt:
        print(f"\n{ANSI_DIM}interrompu{ANSI_RESET}")
        events.emit("CANCELLED")
    finally:
        if tunnel_proc:
            tunnel_proc.terminate()


def _print_banner(mode: str, target: str, url: str, *, tunneled: bool) -> None:
    line = "─" * 48
    print(f"\n{ANSI_FG}{line}")
    mode_label = f"{mode} (TUNNEL)" if tunneled else mode
    print(f"  qshare // {mode_label}")
    print(f"  {ANSI_DIM}cible : {ANSI_FG}{target}")
    print(f"  {ANSI_DIM}url   : {ANSI_FG}{url}")
    print(f"{line}{ANSI_RESET}\n")
    print_qr(url)
    hint = "QR public, accessible depuis Internet (4G OK)." if tunneled \
           else "QR LAN, même Wi-Fi requis."
    print(f"\n{ANSI_DIM}{hint} Ctrl-C pour arrêter.{ANSI_RESET}\n")


# ─── CLI ──────────────────────────────────────────────────────────────────────
def main() -> None:
    p = argparse.ArgumentParser(prog="qshare",
        description="Partage de fichiers PC <-> tél via HTTP + QR")
    sub = p.add_subparsers(dest="cmd", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("-p", "--port", type=int, default=0)
    common.add_argument("-i", "--iface")
    common.add_argument("-k", "--keep-alive", action="store_true")
    common.add_argument("-t", "--tunnel", action="store_true")
    common.add_argument("--qr-out", help="Écrire un PNG du QR à ce chemin (pour Quickshell)")
    common.add_argument("--event-file", help="Fichier d'événements pour IPC Quickshell")

    sp_send = sub.add_parser("send", parents=[common])
    sp_send.add_argument("paths", nargs="+")
    sp_send.set_defaults(func=cmd_send)

    sp_recv = sub.add_parser("recv", parents=[common])
    sp_recv.add_argument("-o", "--output", default=os.getcwd())
    sp_recv.set_defaults(func=cmd_recv)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()