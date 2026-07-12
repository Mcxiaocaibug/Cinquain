#!/usr/bin/env python3
"""Validation and atomic configuration writer shared by CLI and web panel."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
DEFAULT_IMAGE = f"ghcr.io/mcxiaocaibug/cinquain:{VERSION}"
DEFAULT_CADDY_IMAGE = "docker.io/caddy:2.11.4-alpine"

DOMAIN_RE = re.compile(r"(?=^.{4,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\Z")
EMAIL_RE = re.compile(r"(?=^.{3,254}\Z)[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")
IMAGE_RE = re.compile(r"(?=^.{3,512}\Z)[a-z0-9]+(?:[._-][a-z0-9]+)*(?::[0-9]+)?(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*(?::[A-Za-z0-9][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})?\Z")
STACK_RE = re.compile(r"[a-z0-9][a-z0-9_-]{0,62}\Z")
TIMEZONE_RE = re.compile(r"[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*\Z")


class ConfigError(ValueError):
    pass


def normalize_domain(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"^https?://", "", value)
    value = value.split("/", 1)[0].rstrip(".")
    if value.endswith(":443"):
        value = value[:-4]
    return value


def validate_domain(value: str) -> str:
    value = normalize_domain(value)
    if not DOMAIN_RE.fullmatch(value):
        raise ConfigError("Matrix 域名无效；请输入完整 DNS 名称，例如 matrix.example.com。")
    return value


def validate_email(value: str) -> str:
    value = value.strip()
    if not EMAIL_RE.fullmatch(value):
        raise ConfigError("管理员邮箱格式无效。")
    return value


def validate_image(value: str) -> str:
    value = value.strip().lower() if "@sha256:" in value else value.strip()
    if not IMAGE_RE.fullmatch(value):
        raise ConfigError("容器镜像引用无效。")
    return value


def validate_stack(value: str) -> str:
    value = value.strip().lower()
    if not STACK_RE.fullmatch(value):
        raise ConfigError("Compose 项目名只能包含小写字母、数字、下划线和连字符。")
    return value


def validate_timezone(value: str) -> str:
    value = value.strip()
    if ".." in value or not TIMEZONE_RE.fullmatch(value):
        raise ConfigError("时区无效，例如 Asia/Shanghai 或 UTC。")
    return value


def read_env(path: Path | None = None) -> dict[str, str]:
    path = path or ROOT / ".env"
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            values[key] = value
    return values


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_name, mode)
        os.replace(temp_name, path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


@dataclass(frozen=True)
class DeploymentConfig:
    domain: str
    email: str
    image: str = DEFAULT_IMAGE
    caddy_image: str = DEFAULT_CADDY_IMAGE
    stack: str = "cinquain"
    timezone: str = "UTC"
    http_port: int = 80
    https_port: int = 443
    backup_retention: int = 7
    log_level: str = "info"

    @classmethod
    def validated(cls, **values: object) -> "DeploymentConfig":
        try:
            http_port = int(values.get("http_port", 80))
            https_port = int(values.get("https_port", 443))
            retention = int(values.get("backup_retention", 7))
        except (TypeError, ValueError) as exc:
            raise ConfigError("端口和备份保留数量必须是整数。") from exc
        if not 1 <= http_port <= 65535 or not 1 <= https_port <= 65535 or http_port == https_port:
            raise ConfigError("HTTP/HTTPS 端口必须不同，且处于 1-65535。")
        if not 1 <= retention <= 365:
            raise ConfigError("备份保留数量必须处于 1-365。")
        log_level = str(values.get("log_level", "info")).strip().lower()
        if log_level not in {"error", "warn", "info", "debug"}:
            raise ConfigError("日志级别必须是 error、warn、info 或 debug。")
        return cls(
            domain=validate_domain(str(values.get("domain", ""))),
            email=validate_email(str(values.get("email", ""))),
            image=validate_image(str(values.get("image", DEFAULT_IMAGE))),
            caddy_image=validate_image(str(values.get("caddy_image", DEFAULT_CADDY_IMAGE))),
            stack=validate_stack(str(values.get("stack", "cinquain"))),
            timezone=validate_timezone(str(values.get("timezone", "UTC"))),
            http_port=http_port,
            https_port=https_port,
            backup_retention=retention,
            log_level=log_level,
        )

    def env_text(self) -> str:
        return "\n".join(
            [
                "# Managed by Cinquain. Permissions must remain 0600.",
                f"CINQUAIN_VERSION={VERSION}",
                "CINQUAIN_CONFIG_REVISION=1",
                f"CINQUAIN_STACK_NAME={self.stack}",
                f"CINQUAIN_SERVER_NAME={self.domain}",
                f"CINQUAIN_OPERATOR_EMAIL={self.email}",
                f"CINQUAIN_HOMESERVER_IMAGE={self.image}",
                f"CINQUAIN_CADDY_IMAGE={self.caddy_image}",
                f"CINQUAIN_HTTP_PORT={self.http_port}",
                f"CINQUAIN_HTTPS_PORT={self.https_port}",
                f"CINQUAIN_BACKUP_RETENTION={self.backup_retention}",
                f"CINQUAIN_LOG_LEVEL={self.log_level}",
                f"CINQUAIN_TIMEZONE={self.timezone}",
                "",
            ]
        )

    def toml_text(self) -> str:
        return f'''# Managed by Cinquain {VERSION}. server_name is immutable after first deployment.
[global]
server_name = "{self.domain}"
database_path = "/var/lib/continuwuity"
address = ["0.0.0.0"]
port = 8008
allow_registration = false
allow_federation = true
request_ip_source = "x_forwarded_for"

[global.well_known]
client = "https://{self.domain}"
server = "{self.domain}:{self.https_port}"
support_page = "https://{self.domain}/support/"
support_email = "{self.email}"
'''


def write_config(config: DeploymentConfig, root: Path = ROOT) -> None:
    lock_path = root / "state" / "server-name.lock"
    locked_domain = lock_path.read_text(encoding="utf-8").strip() if lock_path.exists() else ""
    if locked_domain and locked_domain != config.domain:
        raise ConfigError(
            f"server_name 已锁定为 {locked_domain}。Matrix 身份域不能在保留数据库时修改。"
        )
    atomic_write(root / ".env", config.env_text())
    atomic_write(root / "continuwuity.toml", config.toml_text())
    state = root / "state"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(state, 0o700)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write validated Cinquain configuration")
    parser.add_argument("domain")
    parser.add_argument("email")
    parser.add_argument("--image", default=DEFAULT_IMAGE)
    parser.add_argument("--caddy-image", default=DEFAULT_CADDY_IMAGE)
    parser.add_argument("--stack", default="cinquain")
    parser.add_argument("--timezone", default="UTC")
    parser.add_argument("--http-port", type=int, default=80)
    parser.add_argument("--https-port", type=int, default=443)
    parser.add_argument("--backup-retention", type=int, default=7)
    parser.add_argument("--log-level", default="info")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        config = DeploymentConfig.validated(**vars(args))
        write_config(config)
    except ConfigError as exc:
        print(f"配置错误: {exc}", file=os.sys.stderr)
        return 2
    print(f"已写入 {ROOT / '.env'} 和 {ROOT / 'continuwuity.toml'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
