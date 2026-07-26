from __future__ import annotations

import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parents[1] / "lib" / "config.py"
SPEC = importlib.util.spec_from_file_location("cinquain_config", CONFIG_PATH)
assert SPEC and SPEC.loader
config = importlib.util.module_from_spec(SPEC)
import sys
sys.modules[SPEC.name] = config
SPEC.loader.exec_module(config)


class ConfigTests(unittest.TestCase):
    def test_normalizes_and_validates_domain(self) -> None:
        self.assertEqual(config.validate_domain(" HTTPS://Matrix.Example.COM:443/path "), "matrix.example.com")
        for invalid in ("localhost", "127.0.0.1", "bad domain.example", "-bad.example.com"):
            with self.subTest(invalid=invalid), self.assertRaises(config.ConfigError):
                config.validate_domain(invalid)

    def test_validates_email_image_and_timezone(self) -> None:
        self.assertEqual(config.validate_email("ops+matrix@example.org"), "ops+matrix@example.org")
        self.assertEqual(config.validate_image("ghcr.io/example/cinquain:0.0.1"), "ghcr.io/example/cinquain:0.0.1")
        self.assertEqual(config.validate_timezone("Asia/Shanghai"), "Asia/Shanghai")
        for invalid in ("image with spaces", "UPPER.example/Repo:tag", "https://registry/image"):
            with self.subTest(invalid=invalid), self.assertRaises(config.ConfigError):
                config.validate_image(invalid)
        with self.assertRaises(config.ConfigError):
            config.validate_timezone("../etc/passwd")

    def test_writes_atomic_private_configuration_and_locks_domain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            deployment = config.DeploymentConfig.validated(
                domain="matrix.example.org", email="ops@example.org", timezone="Asia/Shanghai"
            )
            config.write_config(deployment, root)
            env_text = (root / ".env").read_text(encoding="utf-8")
            toml_text = (root / "continuwuity.toml").read_text(encoding="utf-8")
            # Derived, not literal: a hardcoded version here fails the suite on
            # every release bump without testing anything extra.
            self.assertIn(f"CINQUAIN_VERSION={config.VERSION}", env_text)
            self.assertIn("server_name = \"matrix.example.org\"", toml_text)
            self.assertEqual(stat.S_IMODE(os.stat(root / ".env").st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(os.stat(root / "continuwuity.toml").st_mode), 0o600)
            config.write_config(
                config.DeploymentConfig.validated(domain="other.example.org", email="ops@example.org"), root
            )
            (root / "state" / "server-name.lock").write_text("other.example.org\n", encoding="utf-8")
            with self.assertRaisesRegex(config.ConfigError, "server_name"):
                config.write_config(
                    config.DeploymentConfig.validated(domain="third.example.org", email="ops@example.org"), root
                )

    def test_rejects_unsafe_ports_and_retention(self) -> None:
        base = {"domain": "matrix.example.org", "email": "ops@example.org"}
        with self.assertRaises(config.ConfigError):
            config.DeploymentConfig.validated(**base, http_port=443, https_port=443)
        with self.assertRaises(config.ConfigError):
            config.DeploymentConfig.validated(**base, backup_retention=0)


if __name__ == "__main__":
    unittest.main()
