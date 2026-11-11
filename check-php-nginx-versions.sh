#!/usr/bin/env python3
"""
check-php-nginx-versions.py — проверка версий PHP и Nginx
во всех запущенных Docker-контейнерах.

Использование:
    ./check-php-nginx-versions.py
    ./check-php-nginx-versions.py --json
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field


# Цвета (отключаются, если вывод не в терминал)
if sys.stdout.isatty():
    BOLD = "\033[1m"
    CYAN = "\033[36m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    RESET = "\033[0m"
else:
    BOLD = CYAN = YELLOW = RED = RESET = ""


@dataclass
class CheckResult:
    found: list[tuple[str, str]] = field(default_factory=list)
    not_found: list[str] = field(default_factory=list)
    errors: list[tuple[str, str]] = field(default_factory=list)


def list_containers() -> list[str]:
    out = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}"],
        capture_output=True, text=True, check=True,
    )
    return [line for line in out.stdout.splitlines() if line]


def check_binary(container: str, binary: str, version_cmd: str) -> tuple[str | None, str | None]:
    check = subprocess.run(
        ["docker", "exec", container, "sh", "-c", f"command -v {binary} >/dev/null 2>&1"],
        capture_output=True, text=True,
    )
    if check.returncode != 0:
        return None, None

    result = subprocess.run(
        ["docker", "exec", container, "sh", "-c", version_cmd],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None, result.stderr.strip() or "docker exec failed"

    version = (result.stdout or result.stderr).strip().splitlines()[0]
    return version, None


def audit(containers: list[str], binary: str, version_cmd: str) -> CheckResult:
    res = CheckResult()
    for c in containers:
        version, err = check_binary(c, binary, version_cmd)
        if err:
            res.errors.append((c, err))
        elif version:
            res.found.append((c, version))
        else:
            res.not_found.append(c)
    return res


def print_report(label: str, res: CheckResult) -> None:
    print(f"\n{BOLD}{CYAN}===== {label} ====={RESET}")

    print(f"\n{BOLD}--- {label}: найден ---{RESET}")
    if res.found:
        for name, ver in res.found:
            print(f"  {name:<40} {ver}")
    else:
        print("  (нет)")

    print(f"\n{BOLD}{YELLOW}--- {label}: не найден ---{RESET}")
    if res.not_found:
        for name in res.not_found:
            print(f"  {name}")
    else:
        print("  (нет)")

    print(f"\n{BOLD}{RED}--- {label}: ошибка проверки ---{RESET}")
    if res.errors:
        for name, err in res.errors:
            print(f"  {name:<40} {err}")
    else:
        print("  (нет)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Аудит версий PHP и Nginx в Docker-контейнерах")
    parser.add_argument("--json", action="store_true", help="вывод в JSON")
    args = parser.parse_args()

    try:
        containers = list_containers()
    except subprocess.CalledProcessError as e:
        print(f"Ошибка: не удалось получить список контейнеров: {e}", file=sys.stderr)
        return 1

    php = audit(containers, "php", "php -v 2>/dev/null | head -1")
    nginx = audit(containers, "nginx", "nginx -v 2>&1 | head -1")

    if args.json:
        print(json.dumps({
            "php": {
                "found": [{"container": c, "version": v} for c, v in php.found],
                "not_found": php.not_found,
                "errors": [{"container": c, "error": e} for c, e in php.errors],
            },
            "nginx": {
                "found": [{"container": c, "version": v} for c, v in nginx.found],
                "not_found": nginx.not_found,
                "errors": [{"container": c, "error": e} for c, e in nginx.errors],
            },
        }, ensure_ascii=False, indent=2))
    else:
        print_report("PHP", php)
        print_report("Nginx", nginx)

    return 0


if __name__ == "__main__":
    sys.exit(main())
