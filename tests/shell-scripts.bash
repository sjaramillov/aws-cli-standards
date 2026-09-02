#!/usr/bin/env bash

set -euo pipefail

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN
unset AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_CREDENTIALS_FULL_URI
unset AWS_CONTAINER_AUTHORIZATION_TOKEN AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preflight="${repo_root}/scripts/preflight.sh"
ownership_guard="${repo_root}/scripts/verify-lab-ownership.sh"
renderer="${repo_root}/scripts/render-cluster-config.sh"

export FAKE_AWS_ACCOUNT="123456789012"
export FAKE_AWS_ARN="arn:aws:sts::123456789012:assumed-role/eks-learning/test-session"
export FAKE_EKS_STATUS="STANDARD_SUPPORT"
export FAKE_EKSCTL_VERSION="0.230.0"
export FAKE_KUBECTL_VERSION="1.36.2"
export FAKE_CLUSTER_ARN="arn:aws:eks:us-east-1:123456789012:cluster/eks-learning"
export FAKE_CLUSTER_ENDPOINT="https://EXAMPLE.gr7.us-east-1.eks.amazonaws.com"
export FAKE_PROJECT_TAG="eks-learning"
export FAKE_ENVIRONMENT_TAG="lab"
export FAKE_MANAGED_BY_TAG="eksctl"
export FAKE_OWNER_TAG="ci"
export FAKE_STACK_ID="arn:aws:cloudformation:us-east-1:123456789012:stack/eksctl-eks-learning-cluster/00000000-0000-0000-0000-000000000000"
export FAKE_STACK_STATUS="CREATE_COMPLETE"
export FAKE_KUBE_SERVER="$FAKE_CLUSTER_ENDPOINT"

aws() {
  if [[ "${1:-}" == "--version" ]]; then
    printf 'aws-cli/2.36.30 Python/3.14.7 Linux/6.8 source/x86_64\n'
    return
  fi

  case "${1:-} ${2:-}" in
    "sts get-caller-identity")
      printf '%s\t%s\n' "$FAKE_AWS_ACCOUNT" "$FAKE_AWS_ARN"
      ;;
    "eks describe-cluster-versions")
      printf '%s\n' "$FAKE_EKS_STATUS"
      ;;
    "eks describe-cluster")
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$FAKE_CLUSTER_ARN" "$FAKE_CLUSTER_ENDPOINT" "$FAKE_PROJECT_TAG" "$FAKE_ENVIRONMENT_TAG" \
        "$FAKE_MANAGED_BY_TAG" "$FAKE_OWNER_TAG"
      ;;
    "cloudformation describe-stacks")
      printf '%s\t%s\n' "$FAKE_STACK_ID" "$FAKE_STACK_STATUS"
      ;;
    *)
      printf 'AWS falso: llamada no esperada: %s\n' "$*" >&2
      return 64
      ;;
  esac
}

kubectl() {
  if [[ "${1:-}" == "version" ]]; then
    printf '{"clientVersion":{"gitVersion":"v%s"}}\n' "$FAKE_KUBECTL_VERSION"
    return
  fi
  if [[ "${1:-} ${2:-}" == "config view" ]]; then
    printf '%s' "$FAKE_KUBE_SERVER"
    return
  fi
  printf 'kubectl falso: llamada no esperada: %s\n' "$*" >&2
  return 64
}

eksctl() {
  if [[ "${1:-}" == "version" ]]; then
    printf '%s\n' "$FAKE_EKSCTL_VERSION"
    return
  fi
  printf 'eksctl falso: llamada no esperada: %s\n' "$*" >&2
  return 64
}

export -f aws kubectl eksctl

run_preflight() {
  AWS_PROFILE="test" \
  AWS_REGION="${TEST_AWS_REGION:-us-east-1}" \
  CLUSTER_NAME="${TEST_CLUSTER_NAME:-eks-learning}" \
  EXPECTED_AWS_ACCOUNT_ID="123456789012" \
  EKS_VERSION="${TEST_EKS_VERSION:-1.36}" \
    "$preflight" "$@"
}

render_config() {
  AWS_REGION="us-east-1" \
  CLUSTER_NAME="${TEST_CLUSTER_NAME:-eks-learning}" \
  EKS_VERSION="1.36" \
  PUBLIC_ACCESS_CIDR="203.0.113.10/32" \
  OWNER_TAG="ci" \
  DELETE_AFTER="2099-01-01" \
    "$renderer"
}

run_ownership_guard() {
  AWS_PROFILE="test" \
  AWS_REGION="us-east-1" \
  CLUSTER_NAME="eks-learning" \
  EXPECTED_AWS_ACCOUNT_ID="123456789012" \
  OWNER_TAG="ci" \
  KUBECONFIG="/tmp/eks-learning-test-kubeconfig" \
    "$ownership_guard"
}

fail() {
  printf 'ERROR DE TEST: %s\n' "$1" >&2
  exit 1
}

output="$(run_preflight --for-create 2>&1)" || fail "preflight válido fue rechazado"
[[ "$output" == *"STANDARD_SUPPORT"* ]] || fail "preflight no informó el soporte"

TEST_AWS_REGION="eusc-de-east-1" \
FAKE_CLUSTER_ARN="arn:aws:eks:eusc-de-east-1:123456789012:cluster/eks-learning" \
  run_preflight --for-create >/dev/null 2>&1 || fail "región con prefijo largo fue rechazada"

if FAKE_AWS_ACCOUNT="999999999999" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight aceptó una cuenta distinta"
fi

if (export AWS_ACCESS_KEY_ID="presente"; run_preflight --for-create >/dev/null 2>&1); then
  fail "preflight aceptó credenciales AWS de entorno que prevalecen sobre el perfil"
fi

if FAKE_AWS_ARN="arn:aws:iam::123456789012:root" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight aceptó el usuario raíz"
fi

if FAKE_EKSCTL_VERSION="0.229.0" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight de creación aceptó eksctl anterior al mínimo"
fi

if FAKE_KUBECTL_VERSION="1.33.9" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight aceptó kubectl a más de una minor"
fi

if TEST_EKS_VERSION="1.036" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight aceptó una versión EKS con ceros iniciales"
fi

cluster_name_99="$(printf 'a%.0s' {1..99})"
TEST_CLUSTER_NAME="$cluster_name_99" run_preflight --for-create >/dev/null 2>&1 \
  || fail "preflight rechazó un nombre de clúster de 99 caracteres"
TEST_CLUSTER_NAME="$cluster_name_99" render_config >/dev/null 2>&1 \
  || fail "renderer rechazó un nombre de clúster de 99 caracteres"

cluster_name_100="${cluster_name_99}a"
if TEST_CLUSTER_NAME="$cluster_name_100" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight aceptó un nombre de clúster de 100 caracteres"
fi
if TEST_CLUSTER_NAME="$cluster_name_100" render_config >/dev/null 2>&1; then
  fail "renderer aceptó un nombre de clúster de 100 caracteres"
fi

if FAKE_EKS_STATUS="EXTENDED_SUPPORT" run_preflight --for-create >/dev/null 2>&1; then
  fail "preflight de creación aceptó soporte extendido"
fi

output="$(FAKE_EKS_STATUS="EXTENDED_SUPPORT" run_preflight 2>&1)" \
  || fail "modo de inspección rechazó soporte extendido"
[[ "$output" == *"ADVERTENCIA"* ]] || fail "modo de inspección omitió la advertencia"

run_ownership_guard >/dev/null 2>&1 || fail "guard de propiedad válido fue rechazado"

if FAKE_OWNER_TAG="otra-persona" run_ownership_guard >/dev/null 2>&1; then
  fail "guard aceptó un Owner distinto"
fi

if FAKE_STACK_STATUS="DELETE_COMPLETE" run_ownership_guard >/dev/null 2>&1; then
  fail "guard aceptó un stack eliminado"
fi

if FAKE_STACK_STATUS="DELETE_IN_PROGRESS" run_ownership_guard >/dev/null 2>&1; then
  fail "guard aceptó un stack en eliminación"
fi

if FAKE_CLUSTER_ARN="arn:aws:eks:us-east-1:999999999999:cluster/eks-learning" \
  run_ownership_guard >/dev/null 2>&1; then
  fail "guard aceptó un ARN de otra cuenta"
fi

if FAKE_KUBE_SERVER="https://OTHER.gr7.us-east-1.eks.amazonaws.com" \
  run_ownership_guard >/dev/null 2>&1; then
  fail "guard aceptó un kubeconfig que apunta a otro endpoint"
fi

printf 'OK: preflight y guard de propiedad verificados con dobles locales\n'
