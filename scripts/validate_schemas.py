#!/usr/bin/env python3
"""Validate repository YAML and the rendered ClusterConfig against eksctl's schema."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml
from jsonschema.validators import validator_for


REPO_ROOT = Path(__file__).resolve().parent.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--eksctl", required=True, help="Path to the pinned eksctl binary")
    return parser.parse_args()


def load_yaml_documents(path: Path) -> list[object]:
    try:
        documents = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    except yaml.YAMLError as error:
        raise ValueError(f"{path.relative_to(REPO_ROOT)}: YAML inválido: {error}") from error
    if not documents or any(document is None for document in documents):
        raise ValueError(f"{path.relative_to(REPO_ROOT)}: contiene un documento YAML vacío")
    return documents


def render_cluster_config() -> dict[str, object]:
    environment = os.environ.copy()
    environment.update(
        {
            "AWS_REGION": "us-east-1",
            "CLUSTER_NAME": "eks-learning",
            "EKS_VERSION": "1.36",
            "PUBLIC_ACCESS_CIDR": "203.0.113.10/32",
            "OWNER_TAG": "true",
            "DELETE_AFTER": "2099-01-01",
        }
    )
    result = subprocess.run(
        [REPO_ROOT / "scripts" / "render-cluster-config.sh"],
        cwd=REPO_ROOT,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )
    config = yaml.safe_load(result.stdout)
    if not isinstance(config, dict):
        raise ValueError("la configuración renderizada no es un objeto YAML")
    owner = config["metadata"]["tags"]["Owner"]  # type: ignore[index]
    if owner != "true" or not isinstance(owner, str):
        raise ValueError("Owner debe conservarse como string después de renderizar YAML")
    return config


def validate_eksctl(config: dict[str, object], eksctl_path: str) -> None:
    result = subprocess.run(
        [eksctl_path, "utils", "schema"],
        check=True,
        capture_output=True,
        text=True,
    )
    schema = json.loads(result.stdout)
    validator_class = validator_for(schema)
    validator_class.check_schema(schema)
    errors = sorted(
        validator_class(schema).iter_errors(config),
        key=lambda error: [str(part) for part in error.absolute_path],
    )
    if errors:
        formatted = "\n".join(
            f"- {list(error.absolute_path)}: {error.message}" for error in errors
        )
        raise ValueError(f"ClusterConfig no cumple el schema de eksctl:\n{formatted}")


def main() -> int:
    args = parse_args()
    yaml_paths = sorted((REPO_ROOT / ".github").rglob("*.yml"))
    yaml_paths.extend(sorted((REPO_ROOT / ".github").rglob("*.yaml")))
    yaml_paths.append(REPO_ROOT / "examples" / "workloads" / "hello.yaml")

    try:
        for path in yaml_paths:
            load_yaml_documents(path)
        config = render_cluster_config()
        validate_eksctl(config, args.eksctl)
    except (KeyError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(yaml_paths)} archivos YAML y ClusterConfig contra schema de eksctl"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
