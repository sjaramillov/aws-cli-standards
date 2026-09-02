#!/usr/bin/env bash

set -euo pipefail

mode="context"

case "${1:-}" in
  "") ;;
  --for-create) mode="create" ;;
  --help|-h)
    printf 'Uso: %s [--for-create]\n' "$0"
    printf 'Sin opción valida identidad y contexto; --for-create exige una versión en soporte estándar.\n'
    exit 0
    ;;
  *)
    printf 'ERROR: opción no reconocida: %s\n' "$1" >&2
    exit 2
    ;;
esac

if (($# > 1)); then
  printf 'ERROR: se esperaba como máximo una opción\n' >&2
  exit 2
fi

for variable_name in AWS_PROFILE AWS_REGION CLUSTER_NAME EXPECTED_AWS_ACCOUNT_ID; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'ERROR: falta la variable %s\n' "$variable_name" >&2
    exit 1
  fi
done

if [[ ! "$AWS_REGION" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+-[0-9]+$ ]]; then
  printf 'ERROR: AWS_REGION no parece una región válida: %s\n' "$AWS_REGION" >&2
  exit 1
fi

if [[ ! "$CLUSTER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,98}$ ]]; then
  printf 'ERROR: CLUSTER_NAME debe tener 1-99 caracteres válidos para este laboratorio\n' >&2
  exit 1
fi

if [[ ! "$EXPECTED_AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
  printf 'ERROR: EXPECTED_AWS_ACCOUNT_ID debe contener exactamente 12 dígitos\n' >&2
  exit 1
fi

if [[ -n "${EKS_VERSION:-}" && ! "$EKS_VERSION" =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)$ ]]; then
  printf 'ERROR: EKS_VERSION debe tener formato mayor.minor sin ceros iniciales, por ejemplo 1.36\n' >&2
  exit 1
fi

if [[ "$mode" == "create" && -z "${EKS_VERSION:-}" ]]; then
  printf 'ERROR: --for-create requiere EKS_VERSION\n' >&2
  exit 1
fi

credential_environment_variables=(
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN
  AWS_SECURITY_TOKEN
  AWS_WEB_IDENTITY_TOKEN_FILE
  AWS_ROLE_ARN
  AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
  AWS_CONTAINER_CREDENTIALS_FULL_URI
  AWS_CONTAINER_AUTHORIZATION_TOKEN
  AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE
)

for credential_variable in "${credential_environment_variables[@]}"; do
  if [[ -n "${!credential_variable:-}" ]]; then
    printf 'ERROR: %s está definida y puede hacer que eksctl ignore el perfil esperado\n' \
      "$credential_variable" >&2
    printf 'Usa una terminal limpia y credenciales temporales obtenidas mediante AWS_PROFILE.\n' >&2
    exit 1
  fi
done

for binary_name in aws kubectl eksctl; do
  if ! command -v "$binary_name" >/dev/null 2>&1; then
    printf 'ERROR: no se encontró %s en PATH\n' "$binary_name" >&2
    exit 1
  fi
done

aws_version="$(aws --version 2>&1)"
if [[ "$aws_version" != aws-cli/2.* ]]; then
  printf 'ERROR: esta guía requiere AWS CLI v2; encontrado: %s\n' "$aws_version" >&2
  exit 1
fi

kubectl_version_json="$(kubectl version --client --output=json 2>/dev/null)"
if [[ "$kubectl_version_json" =~ \"gitVersion\"[[:space:]]*:[[:space:]]*\"v([0-9]+)\.([0-9]+) ]]; then
  kubectl_major="${BASH_REMATCH[1]}"
  kubectl_minor="${BASH_REMATCH[2]}"
else
  printf 'ERROR: no se pudo determinar la versión minor de kubectl\n' >&2
  exit 1
fi

eksctl_version="$(eksctl version)"
if [[ "$eksctl_version" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  eksctl_major="${BASH_REMATCH[1]}"
  eksctl_minor="${BASH_REMATCH[2]}"
else
  printf 'ERROR: no se pudo interpretar la versión de eksctl: %s\n' "$eksctl_version" >&2
  exit 1
fi

if ((eksctl_major == 0 && eksctl_minor < 230)); then
  if [[ "$mode" == "create" ]]; then
    printf 'ERROR: esta revisión requiere eksctl 0.230.0 o posterior para crear\n' >&2
    exit 1
  fi
  printf 'ADVERTENCIA: eksctl %s es anterior a la versión 0.230.0 verificada por esta guía\n' \
    "$eksctl_version" >&2
fi

read -r actual_account actual_arn < <(
  aws sts get-caller-identity \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query '[Account,Arn]' \
    --output text
)

if [[ "$actual_arn" == *":root" ]]; then
  printf 'ERROR: no uses el usuario raíz para este laboratorio\n' >&2
  exit 1
fi

if [[ "$actual_account" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
  printf 'ERROR: la cuenta real %s no coincide con EXPECTED_AWS_ACCOUNT_ID\n' "$actual_account" >&2
  exit 1
fi

printf 'AWS CLI: %s\n' "$aws_version"
printf 'kubectl: %s.%s\n' "$kubectl_major" "$kubectl_minor"
printf 'eksctl: %s\n' "$eksctl_version"
printf 'Cuenta: %s\n' "$actual_account"
printf 'Principal: %s\n' "$actual_arn"
printf 'Región: %s\n' "$AWS_REGION"
printf 'Clúster objetivo: %s\n' "$CLUSTER_NAME"

if [[ -n "${EKS_VERSION:-}" ]]; then
  version_status="$(
    aws eks describe-cluster-versions \
      --profile "$AWS_PROFILE" \
      --region "$AWS_REGION" \
      --cluster-versions "$EKS_VERSION" \
      --query 'clusterVersions[0].versionStatus' \
      --output text
  )"

  eks_major="${EKS_VERSION%%.*}"
  eks_minor="${EKS_VERSION#*.}"
  kubectl_minor_distance=$((kubectl_minor - eks_minor))
  if ((kubectl_minor_distance < 0)); then
    kubectl_minor_distance=$((-kubectl_minor_distance))
  fi

  if ((kubectl_major != eks_major || kubectl_minor_distance > 1)); then
    if [[ "$mode" == "create" ]]; then
      printf 'ERROR: kubectl %s.%s está a más de una minor de EKS %s\n' \
        "$kubectl_major" "$kubectl_minor" "$EKS_VERSION" >&2
      exit 1
    fi
    printf 'ADVERTENCIA: kubectl %s.%s no está dentro de una minor de EKS %s\n' \
      "$kubectl_major" "$kubectl_minor" "$EKS_VERSION" >&2
  fi

  if [[ "$version_status" != "STANDARD_SUPPORT" && "$mode" == "create" ]]; then
    printf 'ERROR: EKS_VERSION=%s tiene estado %s, no STANDARD_SUPPORT\n' "$EKS_VERSION" "$version_status" >&2
    exit 1
  fi

  printf 'Versión EKS: %s (%s)\n' "$EKS_VERSION" "$version_status"
  if [[ "$version_status" != "STANDARD_SUPPORT" ]]; then
    printf 'ADVERTENCIA: la versión no está en soporte estándar; no crees un clúster nuevo con ella\n' >&2
  fi
else
  printf 'Versión EKS: no indicada (aceptable para inspección o limpieza)\n'
fi

printf 'Preflight de solo lectura completado (modo %s).\n' "$mode"
