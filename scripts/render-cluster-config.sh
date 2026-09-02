#!/usr/bin/env bash

set -euo pipefail

required=(
  AWS_REGION
  CLUSTER_NAME
  EKS_VERSION
  PUBLIC_ACCESS_CIDR
  OWNER_TAG
  DELETE_AFTER
)

for variable_name in "${required[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Falta la variable requerida %s\n' "$variable_name" >&2
    exit 1
  fi
done

if [[ ! "$CLUSTER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,98}$ ]]; then
  printf 'CLUSTER_NAME debe tener 1-99 caracteres válidos para este laboratorio\n' >&2
  exit 1
fi

if [[ ! "$AWS_REGION" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+-[0-9]+$ ]]; then
  printf 'AWS_REGION no parece una región de AWS válida\n' >&2
  exit 1
fi

if [[ ! "$EKS_VERSION" =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)$ ]]; then
  printf 'EKS_VERSION debe tener formato mayor.minor sin ceros iniciales, por ejemplo 1.36\n' >&2
  exit 1
fi

if [[ ! "$PUBLIC_ACCESS_CIDR" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
  printf 'PUBLIC_ACCESS_CIDR debe ser un CIDR IPv4, por ejemplo 203.0.113.10/32\n' >&2
  exit 1
fi

for cidr_octet in "${BASH_REMATCH[@]:1:4}"; do
  if [[ "$cidr_octet" != "0" && "$cidr_octet" == 0* ]]; then
    printf 'PUBLIC_ACCESS_CIDR debe usar notación IPv4 canónica, sin ceros iniciales\n' >&2
    exit 1
  fi
  if ((10#$cidr_octet > 255)); then
    printf 'PUBLIC_ACCESS_CIDR contiene un octeto IPv4 fuera de rango\n' >&2
    exit 1
  fi
done

if ((10#${BASH_REMATCH[5]} != 32)); then
  printf 'PUBLIC_ACCESS_CIDR debe ser un /32 para este laboratorio\n' >&2
  exit 1
fi

if [[ ! "$OWNER_TAG" =~ ^[A-Za-z0-9_.@-]{1,128}$ ]]; then
  printf 'OWNER_TAG debe tener 1-128 caracteres: letras, números, punto, guion, guion bajo o @\n' >&2
  exit 1
fi

if [[ ! "$DELETE_AFTER" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
  printf 'DELETE_AFTER debe tener formato YYYY-MM-DD\n' >&2
  exit 1
fi

delete_year="${BASH_REMATCH[1]}"
delete_month="${BASH_REMATCH[2]}"
delete_day="${BASH_REMATCH[3]}"
month_number=$((10#$delete_month))
day_number=$((10#$delete_day))

case "$month_number" in
  1|3|5|7|8|10|12) max_day=31 ;;
  4|6|9|11) max_day=30 ;;
  2)
    max_day=28
    if ((10#$delete_year % 400 == 0 || (10#$delete_year % 4 == 0 && 10#$delete_year % 100 != 0))); then
      max_day=29
    fi
    ;;
  *)
    printf 'DELETE_AFTER contiene un mes inválido\n' >&2
    exit 1
    ;;
esac

if ((day_number < 1 || day_number > max_day)); then
  printf 'DELETE_AFTER contiene un día inválido para el mes indicado\n' >&2
  exit 1
fi

today="$(date +%Y-%m-%d)"
if [[ "$DELETE_AFTER" < "$today" ]]; then
  printf 'DELETE_AFTER no puede ser una fecha pasada\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_path="${script_dir}/../examples/eksctl/cluster-lab.yaml.tmpl"

sed \
  -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__EKS_VERSION__|${EKS_VERSION}|g" \
  -e "s|__PUBLIC_ACCESS_CIDR__|${PUBLIC_ACCESS_CIDR}|g" \
  -e "s|__OWNER_TAG__|${OWNER_TAG}|g" \
  -e "s|__DELETE_AFTER__|${DELETE_AFTER}|g" \
  "$template_path"
