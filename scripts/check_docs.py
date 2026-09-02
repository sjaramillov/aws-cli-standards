#!/usr/bin/env python3
"""Checks deterministic documentation invariants without external dependencies."""

from __future__ import annotations

import re
import subprocess
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote


REPO_ROOT = Path(__file__).resolve().parent.parent
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
BASH_FENCE_RE = re.compile(
    r"^```(?:bash|sh)[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL
)
SECRET_PATTERNS = (
    ("AWS access key ID", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    (
        "AWS secret access key",
        re.compile(r"aws_secret_access_key\s*[=:]\s*[A-Za-z0-9/+=]{20,}", re.IGNORECASE),
    ),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,255}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{70,255}\b")),
    (
        "private key",
        re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"),
    ),
    (
        "kubeconfig client key",
        re.compile(r"^\s*client-key-data:\s*[A-Za-z0-9+/=]{40,}\s*$", re.MULTILINE),
    ),
)
TEXT_SUFFIXES = {".md", ".py", ".sh", ".bash", ".yaml", ".yml", ".tmpl", ".txt", ".toml"}
TEXT_FILENAMES = {"Makefile", ".gitignore"}
MUTATION_GUARDS = (
    ("eksctl create cluster", "./scripts/preflight.sh --for-create &&"),
    ("eksctl delete cluster", "./scripts/verify-lab-ownership.sh &&"),
    ("kubectl apply -f", "./scripts/verify-lab-ownership.sh &&"),
    ("kubectl delete -f", "./scripts/verify-lab-ownership.sh &&"),
    ("kubectl set image", "./scripts/verify-lab-ownership.sh &&"),
    ("kubectl rollout undo", "./scripts/verify-lab-ownership.sh &&"),
    ("aws eks update-cluster-config", "./scripts/verify-lab-ownership.sh &&"),
    ("aws eks create-access-entry", "./scripts/verify-lab-ownership.sh &&"),
    ("aws eks associate-access-policy", "./scripts/verify-lab-ownership.sh &&"),
    ("aws eks disassociate-access-policy", "./scripts/verify-lab-ownership.sh &&"),
    ("aws eks delete-access-entry", "./scripts/verify-lab-ownership.sh &&"),
)


def github_slug(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = text.replace("`", "").strip().lower()
    chars: list[str] = []
    for char in text:
        category = unicodedata.category(char)
        if char.isspace():
            chars.append("-")
        elif char in "-_" or category.startswith(("L", "N")):
            chars.append(char)
    return "".join(chars)


def anchors_for(markdown: Path) -> set[str]:
    counts: dict[str, int] = defaultdict(int)
    anchors: set[str] = set()
    for line in markdown.read_text(encoding="utf-8").splitlines():
        match = HEADING_RE.match(line)
        if not match:
            continue
        base = github_slug(match.group(2))
        suffix = counts[base]
        counts[base] += 1
        anchors.add(base if suffix == 0 else f"{base}-{suffix}")
    return anchors


def split_target(raw_target: str) -> tuple[str, str]:
    target = raw_target.strip().strip("<>")
    if " " in target and not target.startswith(("http://", "https://")):
        target = target.split(" ", 1)[0]
    path_part, separator, fragment = target.partition("#")
    return unquote(path_part), unquote(fragment) if separator else ""


def check_markdown(markdown: Path, all_anchors: dict[Path, set[str]]) -> list[str]:
    relative = markdown.relative_to(REPO_ROOT)
    text = markdown.read_text(encoding="utf-8")
    errors: list[str] = []

    if "<img" in text.lower():
        errors.append(f"{relative}: usa imágenes Markdown con alt descriptivo, no HTML <img>")
    if re.search(r"\]\((?:link|todo|tbd)\)", text, re.IGNORECASE):
        errors.append(f"{relative}: contiene un enlace placeholder")
    if text.count("```") % 2:
        errors.append(f"{relative}: número impar de cercas de código ```")

    h1_count = sum(1 for line in text.splitlines() if re.match(r"^#\s+", line))
    if h1_count != 1:
        errors.append(f"{relative}: esperaba exactamente un H1 y encontró {h1_count}")

    for block_number, bash_block in enumerate(BASH_FENCE_RE.findall(text), start=1):
        result = subprocess.run(
            ["bash", "-n"],
            input=bash_block,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode:
            diagnostic = " ".join(result.stderr.split())
            errors.append(
                f"{relative}: bloque Bash {block_number} no compila: {diagnostic}"
            )

        for command, required_guard in MUTATION_GUARDS:
            command_position = bash_block.find(command)
            if command_position < 0:
                continue
            guard_position = bash_block.find(required_guard)
            if guard_position < 0 or guard_position > command_position:
                errors.append(
                    f"{relative}: bloque Bash {block_number} ejecuta {command!r} "
                    f"sin la barrera fail-closed {required_guard!r}"
                )

        if (
            "eksctl create cluster" in bash_block
            and "--dry-run" not in bash_block
            and '--profile "$AWS_PROFILE"' not in bash_block
        ):
            errors.append(
                f"{relative}: bloque Bash {block_number} crea con eksctl sin perfil explícito"
            )

    for raw_target in LINK_RE.findall(text):
        if raw_target.startswith(("http://", "https://", "mailto:")):
            continue
        path_part, fragment = split_target(raw_target)
        target_path = markdown if not path_part else (markdown.parent / path_part).resolve()
        try:
            target_path.relative_to(REPO_ROOT)
        except ValueError:
            errors.append(f"{relative}: enlace sale del repositorio: {raw_target}")
            continue
        if not target_path.exists():
            errors.append(f"{relative}: destino interno inexistente: {raw_target}")
            continue
        if fragment and target_path.suffix.lower() == ".md":
            if fragment not in all_anchors.get(target_path, set()):
                errors.append(f"{relative}: ancla inexistente: {raw_target}")

    return errors


def check_repository_secrets() -> list[str]:
    errors: list[str] = []
    for file_path in sorted(REPO_ROOT.rglob("*")):
        if not file_path.is_file() or ".git" in file_path.parts:
            continue
        if file_path.suffix not in TEXT_SUFFIXES and file_path.name not in TEXT_FILENAMES:
            continue
        try:
            text = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                relative = file_path.relative_to(REPO_ROOT)
                errors.append(f"{relative}: posible {label} detectado")
    return errors


def main() -> int:
    markdown_files = sorted(
        path for path in REPO_ROOT.rglob("*.md") if ".git" not in path.parts
    )
    all_anchors = {path.resolve(): anchors_for(path) for path in markdown_files}
    errors: list[str] = []
    for markdown in markdown_files:
        errors.extend(check_markdown(markdown, all_anchors))
    errors.extend(check_repository_secrets())

    for pattern in ("*.yaml", "*.yml"):
        for path in REPO_ROOT.rglob(pattern):
            if ".git" in path.parts:
                continue
            if "\t" in path.read_text(encoding="utf-8"):
                errors.append(f"{path.relative_to(REPO_ROOT)}: YAML contiene tabulaciones")

    if errors:
        print("Errores de documentación:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(markdown_files)} archivos Markdown, "
        f"{sum(len(BASH_FENCE_RE.findall(path.read_text(encoding='utf-8'))) for path in markdown_files)} "
        "bloques Bash, enlaces internos y patrones de secretos verificados"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
