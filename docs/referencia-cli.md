# Referencia de AWS CLI para EKS

Esta hoja sirve para consulta después de completar los capítulos guiados. No reemplaza el orden de dependencias de un
runbook ni convierte comandos mutables en operaciones seguras.

## Convenciones

Todos los ejemplos esperan:

```bash
export AWS_PROFILE="mi-sandbox"
export AWS_REGION="us-east-1"
export CLUSTER_NAME="eks-learning"
export EXPECTED_AWS_ACCOUNT_ID="123456789012"
export OWNER_TAG="mi-usuario"
export AWS_PAGER=""
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"
```

Clasificación:

- **Lectura:** no pretende cambiar AWS ni Kubernetes.
- **Cambio:** modifica configuración o acceso y requiere revisión.
- **Destructivo:** elimina recursos o interrumpe cargas.

Incluye siempre `--profile` y `--region`. `list-clusters` lista únicamente la región seleccionada.
Los ejemplos mutables con guard pertenecen al laboratorio dedicado de la opción B; en un clúster compartido, usa el
procedimiento y el alcance aprobados por su propietario.

## Descubrimiento y versiones — Lectura

```bash
aws eks list-clusters \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --output table

aws eks describe-cluster-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --version-status STANDARD_SUPPORT \
  --query 'clusterVersions[].{Version:clusterVersion,Default:defaultVersion,FinEstandar:endOfStandardSupportDate}' \
  --output table
```

## Estado y salud del clúster — Lectura

```bash
aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Arn:arn,Estado:status,Version:version,Plataforma:platformVersion,Salud:health.issues,Red:resourcesVpcConfig,Acceso:accessConfig,Upgrade:upgradePolicy}' \
  --output yaml

aws eks list-updates \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --output table
```

Describe un update con el ID devuelto:

```bash
export UPDATE_ID="REEMPLAZA_CON_EL_ID_LISTADO"

aws eks describe-update \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --update-id "$UPDATE_ID" \
  --output yaml
```

## Kubeconfig y contexto

Inspecciona el kubeconfig que se generaría, sin escribir archivo — Lectura:

```bash
aws eks update-kubeconfig \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$CLUSTER_NAME" \
  --dry-run
```

Escribe un archivo aislado — Cambio local:

```bash
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"

aws eks update-kubeconfig \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$CLUSTER_NAME" \
  --kubeconfig "$KUBECONFIG"

kubectl config current-context
```

`--role-arn` indica el rol con el que se autenticarán futuras llamadas de `kubectl`. `--assume-role-arn` permite obtener
los datos del clúster en un escenario cross-account. Verifica el resultado con `--dry-run` antes de combinarlos.

## Managed Node Groups

Lectura:

```bash
aws eks list-nodegroups \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table

aws eks describe-nodegroup \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name learning-ng \
  --output yaml
```

Waiter de creación/actualización — Lectura que espera una condición:

```bash
aws eks wait nodegroup-active \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name learning-ng
```

La actualización del plano de control no actualiza automáticamente un Managed Node Group.

## Access Entries

Lectura:

```bash
aws eks list-access-entries \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table

aws eks list-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --output table
```

Ejemplo de acceso de solo vista limitado al namespace del laboratorio — Cambio:

Obtén la aprobación del propietario. En el laboratorio dedicado de la opción B, verifica primero la identidad y la
propiedad; en un clúster compartido, usa el procedimiento del propietario en lugar de este ejemplo. El rol debe existir
y haber sido aprobado: esta guía no lo crea ni le adjunta policies IAM.

Primero resuelve los ARN reales mediante APIs de AWS. No escribas un ARN a mano:

```bash
export PRINCIPAL_ROLE_NAME="eks-learning-viewer"

CLUSTER_ARN="$(aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.arn' \
  --output text)" &&
AWS_PARTITION="${CLUSTER_ARN#arn:}" &&
AWS_PARTITION="${AWS_PARTITION%%:*}" &&
PRINCIPAL_ARN="$(aws iam get-role \
  --profile "$AWS_PROFILE" \
  --role-name "$PRINCIPAL_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)" &&
ACCESS_POLICY_ARN="$(aws eks list-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "accessPolicies[?name=='AmazonEKSViewPolicy'].arn | [0]" \
  --output text)" &&
EXPECTED_ROLE_PREFIX="arn:${AWS_PARTITION}:iam::${EXPECTED_AWS_ACCOUNT_ID}:role/" &&
[[ "$PRINCIPAL_ARN" == "${EXPECTED_ROLE_PREFIX}"* ]] &&
[[ "$ACCESS_POLICY_ARN" == "arn:${AWS_PARTITION}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" ]] &&
export CLUSTER_ARN AWS_PARTITION PRINCIPAL_ARN ACCESS_POLICY_ARN
```

Si cualquier condición falla, no continúes. Después crea exactamente esa entrada:

```bash
./scripts/verify-lab-ownership.sh &&
aws eks create-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --type STANDARD \
  --tags "Project=eks-learning,Environment=lab,Owner=${OWNER_TAG}"
```

Las Access Entries son eventualmente consistentes. Repite únicamente esta lectura si devuelve
`ResourceNotFoundException`; asocia la policy solo cuando AWS devuelva el mismo principal:

```bash
ACCESS_ENTRY_VALUES="$(aws eks describe-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query '[accessEntry.principalArn,accessEntry.type,accessEntry.tags.Project,accessEntry.tags.Environment,accessEntry.tags.Owner,length(accessEntry.kubernetesGroups)]' \
  --output text)" &&
IFS=$'\t' read -r ACCESS_ENTRY_PRINCIPAL ACCESS_ENTRY_TYPE ACCESS_ENTRY_PROJECT ACCESS_ENTRY_ENVIRONMENT ACCESS_ENTRY_OWNER ACCESS_ENTRY_GROUP_COUNT \
  <<< "$ACCESS_ENTRY_VALUES" &&
EXISTING_POLICY_COUNT="$(aws eks list-associated-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query 'length(associatedAccessPolicies)' \
  --output text)" &&
[[ "$ACCESS_ENTRY_PRINCIPAL" == "$PRINCIPAL_ARN" ]] &&
[[ "$ACCESS_ENTRY_TYPE" == "STANDARD" ]] &&
[[ "$ACCESS_ENTRY_PROJECT" == "eks-learning" ]] &&
[[ "$ACCESS_ENTRY_ENVIRONMENT" == "lab" ]] &&
[[ "$ACCESS_ENTRY_OWNER" == "$OWNER_TAG" ]] &&
[[ "$ACCESS_ENTRY_GROUP_COUNT" == "0" ]] &&
[[ "$EXISTING_POLICY_COUNT" == "0" ]] &&
./scripts/verify-lab-ownership.sh &&
aws eks associate-access-policy \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --policy-arn "$ACCESS_POLICY_ARN" \
  --access-scope type=namespace,namespaces=eks-learning
```

Verifica que la asociación aparezca y prueba permisos permitidos y denegados con esa identidad. No reutilices el rol
de ejemplo sin revisar su trust policy y sus usos existentes:

```bash
aws eks list-associated-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query "associatedAccessPolicies[?policyArn=='${ACCESS_POLICY_ARN}'].{Policy:policyArn,Tipo:accessScope.type,Namespaces:accessScope.namespaces}" \
  --output yaml
```

Retiro del ejemplo — Destructivo para ese acceso, no para el clúster:

Mantén la misma terminal o vuelve a ejecutar el bloque de resolución de ARN. Comprueba la entrada y la asociación
exactas antes de retirarla. No retires el acceso que estás usando ni una entrada administrada por otra persona. Si la
entrada tiene otra policy, grupos Kubernetes o etiquetas distintas, estos controles fallan y debes detenerte:

```bash
ACCESS_ENTRY_VALUES="$(aws eks describe-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query '[accessEntry.principalArn,accessEntry.type,accessEntry.tags.Project,accessEntry.tags.Environment,accessEntry.tags.Owner,length(accessEntry.kubernetesGroups)]' \
  --output text)" &&
IFS=$'\t' read -r ACCESS_ENTRY_PRINCIPAL ACCESS_ENTRY_TYPE ACCESS_ENTRY_PROJECT ACCESS_ENTRY_ENVIRONMENT ACCESS_ENTRY_OWNER ACCESS_ENTRY_GROUP_COUNT \
  <<< "$ACCESS_ENTRY_VALUES" &&
TOTAL_POLICY_COUNT="$(aws eks list-associated-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query 'length(associatedAccessPolicies)' \
  --output text)" &&
POLICY_VALUES="$(aws eks list-associated-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query "associatedAccessPolicies[?policyArn=='${ACCESS_POLICY_ARN}'] | [0].[policyArn,accessScope.type,length(accessScope.namespaces),accessScope.namespaces[0]]" \
  --output text)" &&
IFS=$'\t' read -r ASSOCIATED_POLICY_ARN ACCESS_SCOPE_TYPE ACCESS_SCOPE_NAMESPACE_COUNT ACCESS_SCOPE_NAMESPACE \
  <<< "$POLICY_VALUES" &&
[[ "$ACCESS_ENTRY_PRINCIPAL" == "$PRINCIPAL_ARN" ]] &&
[[ "$ACCESS_ENTRY_TYPE" == "STANDARD" ]] &&
[[ "$ACCESS_ENTRY_PROJECT" == "eks-learning" ]] &&
[[ "$ACCESS_ENTRY_ENVIRONMENT" == "lab" ]] &&
[[ "$ACCESS_ENTRY_OWNER" == "$OWNER_TAG" ]] &&
[[ "$ACCESS_ENTRY_GROUP_COUNT" == "0" ]] &&
[[ "$TOTAL_POLICY_COUNT" == "1" ]] &&
[[ "$ASSOCIATED_POLICY_ARN" == "$ACCESS_POLICY_ARN" ]] &&
[[ "$ACCESS_SCOPE_TYPE" == "namespace" ]] &&
[[ "$ACCESS_SCOPE_NAMESPACE_COUNT" == "1" ]] &&
[[ "$ACCESS_SCOPE_NAMESPACE" == "eks-learning" ]] &&
./scripts/verify-lab-ownership.sh &&
aws eks disassociate-access-policy \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --policy-arn "$ACCESS_POLICY_ARN"
```

Espera la propagación repitiendo solo la consulta. Borra la entrada cuando la asociación ya no exista y el principal
siga coincidiendo:

```bash
TOTAL_POLICY_COUNT="$(aws eks list-associated-access-policies \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query 'length(associatedAccessPolicies)' \
  --output text)" &&
ACCESS_ENTRY_VALUES="$(aws eks describe-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN" \
  --query '[accessEntry.principalArn,accessEntry.type,accessEntry.tags.Project,accessEntry.tags.Environment,accessEntry.tags.Owner,length(accessEntry.kubernetesGroups)]' \
  --output text)" &&
IFS=$'\t' read -r ACCESS_ENTRY_PRINCIPAL ACCESS_ENTRY_TYPE ACCESS_ENTRY_PROJECT ACCESS_ENTRY_ENVIRONMENT ACCESS_ENTRY_OWNER ACCESS_ENTRY_GROUP_COUNT \
  <<< "$ACCESS_ENTRY_VALUES" &&
[[ "$TOTAL_POLICY_COUNT" == "0" ]] &&
[[ "$ACCESS_ENTRY_PRINCIPAL" == "$PRINCIPAL_ARN" ]] &&
[[ "$ACCESS_ENTRY_TYPE" == "STANDARD" ]] &&
[[ "$ACCESS_ENTRY_PROJECT" == "eks-learning" ]] &&
[[ "$ACCESS_ENTRY_ENVIRONMENT" == "lab" ]] &&
[[ "$ACCESS_ENTRY_OWNER" == "$OWNER_TAG" ]] &&
[[ "$ACCESS_ENTRY_GROUP_COUNT" == "0" ]] &&
./scripts/verify-lab-ownership.sh &&
aws eks delete-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN"
```

Verifica el retiro:

```bash
aws eks describe-access-entry \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --principal-arn "$PRINCIPAL_ARN"
```

El resultado esperado es `ResourceNotFoundException`; `AccessDenied` no demuestra que la entrada desapareció.

## EKS Pod Identity — Lectura

```bash
aws eks list-pod-identity-associations \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table
```

Crear una asociación requiere un rol con trust policy para `pods.eks.amazonaws.com`, policy mínima y un ServiceAccount
existente. Sigue el procedimiento oficial en lugar de adjuntar policies amplias al rol del nodo.

## Add-ons

Lectura:

```bash
EKS_VERSION="$(aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.version' \
  --output text)"
export EKS_VERSION

aws eks list-addons \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table

aws eks describe-addon \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name vpc-cni \
  --output yaml

aws eks describe-addon-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --addon-name vpc-cni \
  --kubernetes-version "$EKS_VERSION" \
  --output table
```

No crees ni actualices un add-on hasta revisar compatibilidad, configuración actual, identidad IAM y estrategia de
conflictos. VPC CNI, CoreDNS y kube-proxy no se actualizan automáticamente con el plano de control.

## Logs del plano de control — Cambio y costo

Este ejemplo habilita todos los tipos. CloudWatch cobra ingesta y almacenamiento:

```bash
./scripts/verify-lab-ownership.sh &&
UPDATE_ID="$(aws eks update-cluster-config \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
  --query 'update.id' \
  --output text)" &&
export UPDATE_ID

aws eks describe-update \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --update-id "$UPDATE_ID" \
  --query 'update.{Estado:status,Errores:errors}' \
  --output yaml
```

La actualización es asíncrona: repite solo `describe-update` hasta ver `Successful` y no inicies otro update mientras
esté `InProgress`. Configura retención en el log group. La plantilla del laboratorio habilita solo `audit` y
`authenticator` con siete días.

## Endpoint del API server — Cambio de alto impacto

Ejemplo para conservar acceso privado y limitar el público a un CIDR conocido:

```bash
export PUBLIC_ACCESS_CIDR="REEMPLAZA_CON_CIDR_VERIFICADO"

./scripts/verify-lab-ownership.sh &&
UPDATE_ID="$(aws eks update-cluster-config \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="$PUBLIC_ACCESS_CIDR" \
  --query 'update.id' \
  --output text)" &&
export UPDATE_ID

aws eks describe-update \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --update-id "$UPDATE_ID" \
  --query 'update.{Estado:status,Errores:errors}' \
  --output yaml
```

El placeholder no es válido y debe permanecer así hasta que verifiques el CIDR. Confirma IP de salida, VPN, DNS y
rutas antes de aplicar. Una configuración equivocada puede cortar el acceso de personas o nodos. Repite
`describe-update` hasta `Successful` y vuelve a verificar el endpoint desde una red autorizada.

## Upgrades — Cambio de alto impacto

No ejecutes un upgrade desde una hoja de referencia. Revisa Upgrade Insights, APIs deprecadas, salud, capacidad IP,
backups, compatibilidad y rollback. Se actualiza una versión minor a la vez y luego se coordinan nodos, add-ons,
aplicaciones y clientes.

Consulta:

- [actualizar un clúster EKS](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html);
- [buenas prácticas de upgrades](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html);
- [Upgrade Insights](https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html).

## Eliminación — Destructivo

No uses `delete-cluster` como primer paso. Elimina primero recursos Kubernetes con infraestructura externa, luego
Managed Node Groups/Fargate/EKS capabilities, el clúster y, por último, verifica redes, storage, logs y stacks.

Sigue el runbook de [costos y limpieza](06-costos-y-limpieza.md).

## Fuentes oficiales

- [Referencia `aws eks`](https://docs.aws.amazon.com/cli/latest/reference/eks/)
- [Crear kubeconfig](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [Crear Access Entries y consistencia eventual](https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html)
- [Administrar EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
