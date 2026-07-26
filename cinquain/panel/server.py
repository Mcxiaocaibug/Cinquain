#!/usr/bin/env python3
"""Token-protected, dependency-free Cinquain deployment control plane."""

from __future__ import annotations

import hmac
import json
import os
import subprocess
import sys
import threading
import time
from collections import deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(os.environ.get("CINQUAIN_ROOT", Path(__file__).resolve().parents[1])).resolve()
SITE = Path(__file__).resolve().parent / "site"
sys.path.insert(0, str(ROOT / "lib"))

from config import (  # noqa: E402
    ConfigError,
    DEFAULT_CADDY_IMAGE,
    DEFAULT_IMAGE,
    DeploymentConfig,
    VERSION,
    read_env,
    write_config,
)

MAX_BODY = 64 * 1024
MAX_LOG_LINES = 1200


class OperationRunner:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._lines: deque[str] = deque(maxlen=MAX_LOG_LINES)
        self._running = False
        self._name = "idle"
        self._exit_code: int | None = None
        self._started_at: float | None = None

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "running": self._running,
                "name": self._name,
                "exit_code": self._exit_code,
                "started_at": self._started_at,
                "log": "\n".join(self._lines),
            }

    def start(self, name: str, command: list[str]) -> bool:
        with self._lock:
            if self._running:
                return False
            self._running = True
            self._name = name
            self._exit_code = None
            self._started_at = time.time()
            self._lines.clear()
            self._lines.append(f"$ {' '.join(command)}")
        threading.Thread(target=self._run, args=(command,), daemon=True).start()
        return True

    def _run(self, command: list[str]) -> None:
        environment = os.environ.copy()
        environment.pop("CINQUAIN_PANEL_TOKEN", None)
        environment["CINQUAIN_NONINTERACTIVE"] = "1"
        try:
            process = subprocess.Popen(
                command,
                cwd=ROOT,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            assert process.stdout is not None
            for line in process.stdout:
                with self._lock:
                    self._lines.append(line.rstrip())
            exit_code = process.wait()
        except Exception as exc:  # pragma: no cover - defensive service boundary
            with self._lock:
                self._lines.append(f"启动操作失败: {exc}")
            exit_code = 127
        with self._lock:
            self._exit_code = exit_code
            self._running = False


RUNNER = OperationRunner()


def compose_status() -> list[dict[str, object]]:
    if not (ROOT / ".env").exists():
        return []
    command = [
        "docker",
        "compose",
        "--project-directory",
        str(ROOT),
        "--env-file",
        str(ROOT / ".env"),
        "-f",
        str(ROOT / "docker-compose.yml"),
        "ps",
        "--format",
        "json",
    ]
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=12, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0 or not result.stdout.strip():
        return []
    try:
        parsed = json.loads(result.stdout)
        if isinstance(parsed, list):
            return parsed
        if isinstance(parsed, dict):
            return [parsed]
    except json.JSONDecodeError:
        rows = []
        for line in result.stdout.splitlines():
            try:
                value = json.loads(line)
                if isinstance(value, dict):
                    rows.append(value)
            except json.JSONDecodeError:
                continue
        return rows
    return []


def first_registration_token() -> str | None:
    if not (ROOT / ".env").exists():
        return None
    try:
        result = subprocess.run(
            [str(ROOT / "cinquain"), "token"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            # Reads the whole homeserver log, since the first-run banner is printed
            # at startup and cannot be found by tailing.
            timeout=45,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


class PanelHandler(BaseHTTPRequestHandler):
    server_version = "CinquainPanel/0.0.2"

    def log_message(self, fmt: str, *args: object) -> None:
        # Never log a query string: operators may arrive with a legacy query token.
        # Redacting the whole path instead would corrupt every message, because a
        # path of "/" turns each separator in the request line into a redaction.
        message = fmt % args
        split = urlsplit(self.path)
        if split.query or split.fragment:
            message = message.replace(self.path, f"{split.path}?[redacted]", 1)
        print(f"{self.client_address[0]} - {message}", file=sys.stderr)

    def end_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Cache-Control", "no-store")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
            "connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        )
        super().end_headers()

    def _authorized(self) -> bool:
        supplied = self.headers.get("X-Cinquain-Token", "")
        expected = self.server.panel_token  # type: ignore[attr-defined]
        return bool(supplied) and hmac.compare_digest(supplied, expected)

    def _json(self, status: HTTPStatus, payload: object) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _require_auth(self) -> bool:
        if self._authorized():
            return True
        self._json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "面板令牌无效。"})
        return False

    def _read_json(self) -> dict[str, object]:
        raw_length = self.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError as exc:
            raise ConfigError("无效请求长度。") from exc
        if length <= 0 or length > MAX_BODY:
            raise ConfigError("请求正文为空或过大。")
        try:
            value = json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ConfigError("请求不是有效 JSON。") from exc
        if not isinstance(value, dict):
            raise ConfigError("请求必须是 JSON 对象。")
        return value

    def do_GET(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path == "/healthz":
            self._json(HTTPStatus.OK, {"ok": True, "version": VERSION})
            return
        if path.startswith("/api/"):
            if not self._require_auth():
                return
            if path == "/api/status":
                env = read_env(ROOT / ".env")
                self._json(
                    HTTPStatus.OK,
                    {
                        "ok": True,
                        "version": VERSION,
                        "configured": bool(env),
                        "domain_locked": (ROOT / "state" / "server-name.lock").exists(),
                        "domain": env.get("CINQUAIN_SERVER_NAME"),
                        "email": env.get("CINQUAIN_OPERATOR_EMAIL"),
                        "image": env.get("CINQUAIN_HOMESERVER_IMAGE", DEFAULT_IMAGE),
                        "containers": compose_status(),
                        "operation": RUNNER.snapshot(),
                    },
                )
                return
            if path == "/api/operation":
                self._json(HTTPStatus.OK, {"ok": True, "operation": RUNNER.snapshot()})
                return
            if path == "/api/registration-token":
                self._json(HTTPStatus.OK, {"ok": True, "token": first_registration_token()})
                return
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "API 不存在。"})
            return
        self._serve_static(path)

    def do_POST(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if not path.startswith("/api/") or not self._require_auth():
            return
        try:
            payload = self._read_json()
            if path == "/api/deploy":
                if RUNNER.snapshot()["running"]:
                    self._json(HTTPStatus.CONFLICT, {"ok": False, "error": "已有操作正在执行。"})
                    return
                config = DeploymentConfig.validated(
                    domain=payload.get("domain", ""),
                    email=payload.get("email", ""),
                    image=payload.get("image", DEFAULT_IMAGE),
                    caddy_image=payload.get("caddy_image", DEFAULT_CADDY_IMAGE),
                    stack=payload.get("stack", "cinquain"),
                    timezone=payload.get("timezone", "UTC"),
                    http_port=payload.get("http_port", 80),
                    https_port=payload.get("https_port", 443),
                    backup_retention=payload.get("backup_retention", 7),
                    log_level=payload.get("log_level", "info"),
                )
                write_config(config, ROOT)
                if not RUNNER.start("deploy", [str(ROOT / "cinquain"), "deploy"]):
                    raise ConfigError("已有操作正在执行。")
                self._json(HTTPStatus.ACCEPTED, {"ok": True, "message": "部署已启动。"})
                return
            if path == "/api/action":
                action = str(payload.get("action", ""))
                commands = {
                    "doctor": [str(ROOT / "cinquain"), "doctor"],
                    "backup": [str(ROOT / "cinquain"), "backup"],
                }
                if action == "upgrade":
                    image = str(payload.get("image", "")).strip()
                    command = [str(ROOT / "cinquain"), "upgrade"]
                    if image:
                        # Must read this deployment's .env (CINQUAIN_ROOT), not the
                        # one next to the config module.
                        env = read_env(ROOT / ".env")
                        DeploymentConfig.validated(
                            domain=env.get("CINQUAIN_SERVER_NAME", "matrix.invalid"),
                            email=env.get("CINQUAIN_OPERATOR_EMAIL", "invalid@example.com"),
                            image=image,
                        )
                        command.append(image)
                    commands[action] = command
                if action not in commands:
                    raise ConfigError("不支持的运维操作。")
                if not RUNNER.start(action, commands[action]):
                    self._json(HTTPStatus.CONFLICT, {"ok": False, "error": "已有操作正在执行。"})
                    return
                self._json(HTTPStatus.ACCEPTED, {"ok": True, "message": f"{action} 已启动。"})
                return
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "API 不存在。"})
        except ConfigError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})

    def _serve_static(self, path: str) -> None:
        relative = "index.html" if path in {"", "/"} else path.lstrip("/")
        candidate = (SITE / relative).resolve()
        try:
            candidate.relative_to(SITE.resolve())
        except ValueError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not candidate.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        mime = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "application/javascript; charset=utf-8",
            ".svg": "image/svg+xml",
        }.get(candidate.suffix, "application/octet-stream")
        body = candidate.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    token = os.environ.get("CINQUAIN_PANEL_TOKEN", "")
    if len(token) < 32:
        print("CINQUAIN_PANEL_TOKEN must contain at least 32 characters", file=sys.stderr)
        return 2
    bind = os.environ.get("CINQUAIN_PANEL_BIND", "127.0.0.1")
    try:
        port = int(os.environ.get("CINQUAIN_PANEL_PORT", "7080"))
    except ValueError:
        print("CINQUAIN_PANEL_PORT must be an integer", file=sys.stderr)
        return 2
    if not 1 <= port <= 65535:
        print("CINQUAIN_PANEL_PORT must be between 1 and 65535", file=sys.stderr)
        return 2
    server = ThreadingHTTPServer((bind, port), PanelHandler)
    server.panel_token = token  # type: ignore[attr-defined]
    print(f"Cinquain panel listening on http://{bind}:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
