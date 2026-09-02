# 2. Primer clúster

## Objetivo

Conectar en modo seguro un clúster autorizado o crear un laboratorio reproducible con una versión en soporte estándar,
un Managed Node Group AL2023 y una red deliberadamente económica para aprendizaje.

> [!WARNING]
> La opción B crea recursos facturables. Completa primero [prerrequisitos](01-prerrequisitos.md) y lee el procedimiento
> completo de [limpieza](06-costos-y-limpieza.md). La configuración educativa no es una topología de producción.

## Opción A: usar un clúster existente

Esta es la opción preferida si tu organización ofrece un *sandbox*. Confirma el nombre, la región, el perfil, el rol y
un namespace asignado exclusivamente para ti. Usa un archivo kubeconfig separado para no cambiar por accidente otro
contexto:

```bash
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"
export LAB_NAMESPACE="namespace-asignado"

aws eks update-kubeconfig \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$CLUSTER_NAME" \
  --kubeconfig "$KUBECONFIG"

kubectl config current-context
kubectl get namespace "$LAB_NAMESPACE"
kubectl auth can-i get pods --namespace "$LAB_NAMESPACE"
kubectl auth can-i create deployments --namespace "$LAB_NAMESPACE"
```

`update-kubeconfig` cambia el contexto actual del archivo elegido. `--role-arn` configura la identidad que usarán las
llamadas posteriores de `kubectl`; `--assume-role-arn` sirve para recuperar información del clúster en otro account.
No son equivalentes.

Esta ruta termina en conexión e inspección de permisos. El capítulo de operación presupone el clúster dedicado de la
opción B: no lo ejecutes sin que el propietario autorice expresamente el manifiesto, el namespace y los comandos de
lectura global. Nunca ejecutes el runbook de eliminación sobre un clúster proporcionado por otra persona o equipo.

## Opción B: crear el laboratorio con Managed Nodes

### 1. Entender la desviación educativa

La plantilla crea:

- un plano de control EKS en la versión que tú validaste;
- una VPC dedicada de `eksctl`;
- un solo nodo `t3.small` AL2023 en subred pública, sin SSH y con acceso de Pods a IMDS bloqueado;
- autenticación mediante Access Entries (`API`) y acceso administrador inicial para el rol creador;
- endpoint privado y endpoint público limitado a un CIDR indicado;
- sin NAT Gateway;
- logs `audit` y `authenticator` con siete días de retención.

Un nodo y subred pública reducen el costo y hacen visible la infraestructura, pero no ofrecen alta disponibilidad ni
el aislamiento esperado en producción. El endpoint público sigue requiriendo autenticación; limitar su CIDR reduce la
superficie de red. Si tu IP de salida cambia, tendrás que actualizar el CIDR. El administrador inicial simplifica el
laboratorio, pero tampoco es el modelo objetivo de producción: allí el bootstrap se deshabilita o transfiere a una
identidad de emergencia controlada.

### 2. Preparar la plantilla

Conserva las variables del capítulo anterior y define las que faltan. `PUBLIC_ACCESS_CIDR` debe ser la IP pública de
salida desde la que usarás `kubectl`, normalmente con `/32`; en una red corporativa confírmala con el equipo de red.
La plantilla del laboratorio exige `/32` para impedir que un valor excesivamente amplio pase inadvertido.
También limita `CLUSTER_NAME` a 99 caracteres: [`eksctl` deriva el nombre del stack del node group](https://docs.aws.amazon.com/eks/latest/eksctl/faq.html#nodegroups) y
[CloudFormation admite como máximo 128 caracteres](https://docs.aws.amazon.com/AWSCloudFormation/latest/APIReference/API_CreateStack.html#API_CreateStack_RequestParameters).

```bash
export OWNER_TAG="mi-usuario"
export DELETE_AFTER="AAAA-MM-DD"
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"

PUBLIC_IP="$(curl --fail --silent --show-error https://checkip.amazonaws.com)"
export PUBLIC_IP
export PUBLIC_ACCESS_CIDR="${PUBLIC_IP}/32"
printf 'CIDR observado: %s\n' "$PUBLIC_ACCESS_CIDR"
```

Ejecuta `checkip` desde la misma máquina y con la misma VPN/proxy que usará `kubectl`; confirma el resultado con tu
equipo de red. Si no tienes un `/32` estable, no abras un rango amplio para completar el ejercicio: usa conectividad
privada, un entorno controlado o un clúster proporcionado por la organización.

El valor `AAAA-MM-DD` es deliberadamente no funcional: reemplázalo por una fecha real de hoy o futura.
`DELETE_AFTER` es solo una etiqueta para inventario: no programa ni garantiza la eliminación del clúster.

Genera un archivo local que Git ignora:

```bash
./scripts/render-cluster-config.sh > cluster-lab.generated.yaml
```

Inspecciónalo y pide a `eksctl` que lo expanda **sin crear recursos**:

```bash
./scripts/preflight.sh --for-create &&
eksctl create cluster \
  --config-file cluster-lab.generated.yaml \
  --dry-run > cluster-lab.plan.yaml

less cluster-lab.plan.yaml
```

El dry-run usa `AWS_PROFILE`, ya exportado y validado; [`eksctl` no permite combinar `--profile` con
`--dry-run`](https://docs.aws.amazon.com/eks/latest/eksctl/dry-run.html#one-off-options-in-eksctl). La creación real sí
recibe el perfil como flag explícito.

Comprueba especialmente `metadata.name`, `metadata.region`, `metadata.version`, `vpc`, `managedNodeGroups` y etiquetas.
Si el plan muestra AL2, una versión distinta o más nodos de los esperados, detente y actualiza `eksctl` o la plantilla.

### 3. Último control antes de crear

```bash
./scripts/preflight.sh --for-create

aws eks describe-cluster-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-versions "$EKS_VERSION" \
  --query 'clusterVersions[0].versionStatus' \
  --output text
```

La salida debe ser `STANDARD_SUPPORT`. Confirma también que el clúster no existe:

```bash
aws eks list-clusters \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "clusters[?@=='${CLUSTER_NAME}']" \
  --output text
```

La última salida debe estar vacía.

### 4. Crear y esperar

Este es el primer paso que cambia AWS y genera cargos:

```bash
./scripts/preflight.sh --for-create &&
EXISTING_CLUSTER_COUNT="$(aws eks list-clusters \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "length(clusters[?@=='${CLUSTER_NAME}'])" \
  --output text)" &&
[[ "$EXISTING_CLUSTER_COUNT" == "0" ]] &&
./scripts/render-cluster-config.sh > cluster-lab.generated.yaml &&
eksctl create cluster \
  --profile "$AWS_PROFILE" \
  --config-file cluster-lab.generated.yaml \
  --kubeconfig "$KUBECONFIG"
```

El encadenamiento vuelve a comprobar identidad y soporte, exige que el nombre esté libre y regenera el YAML desde las
variables actuales inmediatamente antes de crear. Si cualquier paso falla, `eksctl` no se ejecuta. No separes el
último comando de esas barreras.

`eksctl` espera la creación de los stacks. Comprueba por separado los estados de EKS:

```bash
aws eks wait cluster-active \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"

aws eks wait nodegroup-active \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name learning-ng
```

### 5. Confirmar el kubeconfig aislado y validar

`eksctl` escribió el archivo indicado, no el kubeconfig global. Regénéralo con la AWS CLI para practicar el flujo y
asignar un alias inequívoco:

```bash
aws eks update-kubeconfig \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$CLUSTER_NAME" \
  --kubeconfig "$KUBECONFIG"

kubectl config current-context
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

Criterio de salida:

- el clúster aparece `ACTIVE`;
- el node group aparece `ACTIVE`;
- hay un nodo `Ready`;
- los Pods de sistema dejan de estar `Pending` o `ContainerCreating`;
- el contexto actual coincide con `CLUSTER_NAME`.

## Opción C: explorar EKS Auto Mode

Auto Mode administra más componentes de cómputo, red, balanceo y almacenamiento, y AWS lo presenta como una ruta de
inicio simplificada. También aplica una tarifa adicional sobre los recursos administrados y oculta parte de las
piezas que este laboratorio quiere enseñar.

No ejecutes ambas opciones para el mismo ejercicio. Después de dominar Managed Node Groups, sigue el
[tutorial oficial de EKS Auto Mode con `eksctl`](https://docs.aws.amazon.com/eks/latest/userguide/automode-get-started-eksctl.html)
y compara:

- Node Pools frente a Managed Node Groups;
- componentes integrados frente a add-ons;
- ciclo de actualización y reparación;
- costos y comportamiento de eliminación, especialmente volúmenes EBS.

## Qué cambiar para producción

Como mínimo, evalúa nodos privados en varias AZ, NAT o VPC endpoints, conectividad privada al API server, más de un
nodo, `bootstrapClusterCreatorAdminPermissions: false`, IaC revisado, deletion protection, logging y retención según
política, backups probados, límites de costos y una ruta de actualización. Consulta la
[plantilla empresarial](07-estandar-empresarial.md).

## Fuentes oficiales

- [Creación y administración con `eksctl`](https://docs.aws.amazon.com/eks/latest/eksctl/creating-and-managing-clusters.html)
- [Configuración de VPC en `eksctl`](https://docs.aws.amazon.com/eks/latest/eksctl/vpc-configuration.html)
- [Acceso a endpoints del API server](https://docs.aws.amazon.com/eks/latest/eksctl/vpc-cluster-access.html)
- [Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [`update-kubeconfig` en AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/eks/update-kubeconfig.html)

[← Prerrequisitos](01-prerrequisitos.md) · [Opción A: volver al inicio](../README.md) ·
[Opción B: operación esencial →](03-operacion-esencial.md)
