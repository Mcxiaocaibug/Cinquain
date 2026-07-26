from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

PANEL_PATH = Path(__file__).resolve().parents[1] / "panel" / "server.py"
SPEC = importlib.util.spec_from_file_location("cinquain_panel", PANEL_PATH)
assert SPEC and SPEC.loader
panel = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = panel
SPEC.loader.exec_module(panel)


class FakeRunner:
    def __init__(self) -> None:
        self.command = None

    def snapshot(self):
        return {"running": False, "name": "idle", "exit_code": None, "started_at": None, "log": ""}

    def start(self, name, command):
        self.command = (name, command)
        return True


class PanelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.old_root = panel.ROOT
        self.old_runner = panel.RUNNER
        panel.ROOT = Path(self.temp.name)
        panel.RUNNER = FakeRunner()
        try:
            self.server = panel.ThreadingHTTPServer(("127.0.0.1", 0), panel.PanelHandler)
        except PermissionError:
            self.temp.cleanup()
            panel.ROOT = self.old_root
            panel.RUNNER = self.old_runner
            self.skipTest("sandbox does not permit loopback sockets")
        self.server.panel_token = "a" * 64
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        panel.ROOT = self.old_root
        panel.RUNNER = self.old_runner
        self.temp.cleanup()

    def request(self, path, *, method="GET", body=None, token=True):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["X-Cinquain-Token"] = "a" * 64
        data = json.dumps(body).encode() if body is not None else None
        return urllib.request.urlopen(
            urllib.request.Request(self.base + path, method=method, data=data, headers=headers), timeout=3
        )

    def test_health_and_security_headers(self) -> None:
        with self.request("/healthz", token=False) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["X-Frame-Options"], "DENY")
            self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])

    def test_api_rejects_missing_token(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as context:
            self.request("/api/status", token=False)
        self.assertEqual(context.exception.code, 401)

    def test_deploy_validates_writes_and_starts_operation(self) -> None:
        body = {
            "domain": "matrix.example.org",
            "email": "ops@example.org",
            "image": panel.DEFAULT_IMAGE,
            "timezone": "Asia/Shanghai",
        }
        with self.request("/api/deploy", method="POST", body=body) as response:
            self.assertEqual(response.status, 202)
        self.assertTrue((panel.ROOT / ".env").exists())
        self.assertEqual(panel.RUNNER.command[0], "deploy")

    def test_deploy_rejects_invalid_domain(self) -> None:
        with self.assertRaises(urllib.error.HTTPError) as context:
            self.request(
                "/api/deploy",
                method="POST",
                body={"domain": "localhost", "email": "ops@example.org"},
            )
        self.assertEqual(context.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
