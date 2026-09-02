#!/usr/bin/env bash

set -euo pipefail

for variable_name in AWS_PROFILE AWS_REGION CLUSTER_NAME EXPECTED_AWS_ACCOUNT_ID KUBECONFIG; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'ERROR: falta la variable %s\n' "$variable_name" >&2
    exit 1
  fi
done

expected_owner_tag="${OWNER_TAG:-}"
if [[ -z "$expected_owner_tag" ]]; then
  printf 'ERROR: falta la variable OWNER_TAG\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/preflight.sh"

cluster_values="$(
  aws eks describe-cluster \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --name "$CLUSTER_NAME" \
    --query '[cluster.arn,cluster.endpoint,cluster.tags.Project,cluster.tags.Environment,cluster.tags.ManagedBy,cluster.tags.Owner]' \
    --output text
)"
IFS=$'\t' read -r cluster_arn cluster_endpoint project_tag environment_tag managed_by_tag owner_tag \
  <<< "$cluster_values"

IFS=':' read -r arn_prefix partition service arn_region arn_account arn_resource <<< "$cluster_arn"
if [[ "$arn_prefix" != "arn" || -z "$partition" || "$service" != "eks" || \
      "$arn_region" != "$AWS_REGION" || "$arn_account" != "$EXPECTED_AWS_ACCOUNT_ID" || \
      "$arn_resource" != "cluster/${CLUSTER_NAME}" ]]; then
  printf 'ERROR: el ARN real no coincide con cuenta, región y nombre esperados: %s\n' "$cluster_arn" >&2
  exit 1
fi

kube_server="$(kubectl config view --minify --output=jsonpath='{.clusters[0].cluster.server}')"
if [[ -z "$kube_server" || "$kube_server" != "$cluster_endpoint" ]]; then
  printf 'ERROR: el contexto de KUBECONFIG no apunta al endpoint del clúster AWS verificado\n' >&2
  printf 'EKS=%s\nKubeconfig=%s\n' "$cluster_endpoint" "${kube_server:-vacío}" >&2
  exit 1
fi

if [[ "$project_tag" != "eks-learning" || "$environment_tag" != "lab" || \
      "$managed_by_tag" != "eksctl" || "$owner_tag" != "$expected_owner_tag" ]]; then
  printf 'ERROR: las etiquetas de propiedad no coinciden con el laboratorio esperado\n' >&2
  printf 'Project=%s Environment=%s ManagedBy=%s Owner=%s\n' \
    "$project_tag" "$environment_tag" "$managed_by_tag" "$owner_tag" >&2
  exit 1
fi

read -r stack_id stack_status < <(
  aws cloudformation describe-stacks \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --stack-name "eksctl-${CLUSTER_NAME}-cluster" \
    --query 'Stacks[0].[StackId,StackStatus]' \
    --output text
)

if [[ "$stack_id" != *":stack/eksctl-${CLUSTER_NAME}-cluster/"* ]]; then
  printf 'ERROR: no se encontró el stack esperado de eksctl\n' >&2
  exit 1
fi

case "$stack_status" in
  CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE) ;;
  *)
    printf 'ERROR: el stack de eksctl no está en un estado estable para operar: %s\n' "$stack_status" >&2
    exit 1
    ;;
esac

printf 'Propiedad verificada: %s\n' "$cluster_arn"
printf 'Endpoint de kubeconfig verificado: %s\n' "$kube_server"
printf 'Stack verificado: %s (%s)\n' "$stack_id" "$stack_status"
printf 'La comprobación fue de solo lectura; revisa el inventario antes de borrar.\n'
