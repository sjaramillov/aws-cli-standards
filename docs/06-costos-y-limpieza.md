# 6. Costos y limpieza

## Objetivo

Reconocer los principales generadores de costo, retirar el laboratorio en el orden correcto y verificar residuos.

> [!CAUTION]
> Este runbook elimina únicamente el clúster creado con la opción B y sus recursos. Si usaste un clúster existente,
> detente: elimina solo tu workload según las instrucciones de su propietario; nunca el clúster ni un namespace
> compartido.

## El costo no es solo “el clúster”

Al corte de esta guía, EKS cobra USD 0,10 por clúster/hora en soporte estándar y USD 0,60 por clúster/hora en soporte
extendido. Confirma siempre la [página de precios de EKS](https://aws.amazon.com/eks/pricing/): el valor puede cambiar y
no incluye el resto de la plataforma.

Revisa al menos:

| Componente | Por qué puede seguir cobrando |
| --- | --- |
| Plano de control EKS | Se factura mientras exista el clúster |
| EC2 o Auto Mode | Nodos, capacidad Spot/On-Demand y tarifa de administración aplicable |
| NAT Gateway | Horas y datos procesados, incluso con poco uso |
| IPv4 pública | Cargo horario aplicable |
| ALB/NLB | Horas y unidades de capacidad |
| EBS, snapshots y EFS | Pueden sobrevivir al workload o al clúster según la política |
| CloudWatch | Ingesta, almacenamiento, consultas y retención de logs/métricas |
| Transferencia | Entre AZ, a Internet o entre servicios/regiones |
| AMP, OpenSearch, Backup | Tienen ciclos de vida separados del clúster |

La plantilla de laboratorio deshabilita NAT Gateway y no crea Load Balancer ni PVC, pero aun así cobra por EKS, EC2,
EBS, IPv4 y CloudWatch mientras existan. EKS Auto Mode tiene costos y semántica de retiro distintos.

## Antes de borrar: confirmar objetivo e inventariar

Vuelve a fijar perfil, región, nombre, cuenta esperada, propietario y kubeconfig. Sustituye la ruta por la ubicación real
del clon y ejecuta:

```bash
cd "/ruta/completa/aws-cli-standards"

export AWS_PROFILE="mi-sandbox"
export AWS_REGION="us-east-1"
export CLUSTER_NAME="eks-learning"
export EXPECTED_AWS_ACCOUNT_ID="123456789012"
export OWNER_TAG="mi-usuario"
export AWS_PAGER=""
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"

./scripts/preflight.sh
kubectl config current-context

./scripts/verify-lab-ownership.sh

aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Arn:arn,Estado:status,Proteccion:deletionProtection}' \
  --output table

LAB_VPC_ID="$(aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)"
export LAB_VPC_ID
printf 'VPC que debe desaparecer: %s\n' "$LAB_VPC_ID"
```

El guard falla si ARN, endpoint del kubeconfig, tags `Project`/`Environment`/`ManagedBy`/`Owner` o stack de `eksctl` no
coinciden. No lo desactives para “hacer funcionar” el borrado. No continúes si `LAB_VPC_ID` está vacío, muestra `None` o
no comienza por `vpc-`; esa variable conecta el inventario previo con la comprobación posterior. Después, haz
inventario de los recursos Kubernetes que pueden respaldar infraestructura externa:

```bash
kubectl get services --all-namespaces
kubectl get ingress --all-namespaces
kubectl get persistentvolumeclaims --all-namespaces
kubectl get persistentvolumes
```

Un Service `LoadBalancer`, un Ingress o un PV requiere conocer el controlador y la política de retención antes de
eliminarlo.

## Orden de limpieza del laboratorio

### 1. Eliminar workloads y recursos externos

Para la carga de esta guía:

```bash
./scripts/verify-lab-ownership.sh &&
kubectl delete -f examples/workloads/hello.yaml --ignore-not-found --wait=true
```

Para otras cargas del laboratorio, elimina primero Ingress y Services `LoadBalancer`; espera a que los ALB/NLB y target
groups desaparezcan. Revisa PVC/PV, snapshots, DNS, certificados, Secrets Manager, AMP y recursos creados por
controladores. No borres datos sin confirmar su política de retención.

### 2. Desactivar deletion protection si corresponde

La plantilla educativa no la habilita. Si la activaste intencionalmente:

```bash
./scripts/verify-lab-ownership.sh &&
UPDATE_ID="$(aws eks update-cluster-config \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --no-deletion-protection \
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

La actualización es asíncrona. No continúes hasta que `Estado` sea `Successful`; vuelve a ejecutar únicamente
`describe-update` para observar el estado. Si termina en `Failed` o `Cancelled`, conserva `Errores` y diagnostica.

Deletion protection es una barrera contra accidentes, no una razón para otorgar permisos amplios de eliminación.

### 3. Eliminar con la misma herramienta de creación

Para un clúster creado con `eksctl`, permite que elimine sus Managed Node Groups y stacks:

> [!CAUTION]
> Este flujo exige un laboratorio creado y verificable. Si la creación quedó parcial y el guard falla, sigue
> [la ruta de diagnóstico para creación incompleta](05-solucion-de-problemas.md#la-creación-falló-antes-de-obtener-un-clúster-utilizable)
> con el propietario de la cuenta; no retires la barrera para forzar el borrado.

```bash
./scripts/verify-lab-ownership.sh &&
eksctl delete cluster \
  --profile "$AWS_PROFILE" \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --wait
```

Usa `--wait`: sin él, puedes abandonar una eliminación fallida sin notarlo. Un PodDisruptionBudget puede bloquear el
drenaje; diagnostica antes de considerar opciones que omitan la evicción segura.

No sustituyas este paso por un `aws eks delete-cluster` aislado. La API exige borrar primero Managed Node Groups y
Fargate profiles, y no conoce todo recurso creado por Kubernetes o CloudFormation.

## Verificación posterior

### 1. EKS y CloudFormation

```bash
aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"
```

El resultado esperado es `ResourceNotFoundException`. `AccessDenied` o un error de red **no** demuestran que el clúster
se eliminó.

Revisa stacks restantes:

```bash
aws cloudformation list-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "StackSummaries[?contains(StackName, '${CLUSTER_NAME}') && StackStatus!='DELETE_COMPLETE'].[StackName,StackStatus]" \
  --output table
```

La salida debe estar vacía. Cualquier estado distinto de `DELETE_COMPLETE` —incluidos estados fallidos, rollback o en
progreso— requiere revisar eventos y confirmar si aún conserva recursos.

### 2. Recursos etiquetados

```bash
aws resourcegroupstaggingapi get-resources \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --tag-filters Key=Project,Values=eks-learning Key=Owner,Values="$OWNER_TAG" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table
```

Este inventario ayuda, pero no prueba ausencia: no todos los recursos soportan tags ni todos los tags se propagan.
Complementa la búsqueda por etiquetas con consultas dirigidas de solo lectura. Las consultas por VPC encuentran
recursos aunque no heredaran los tags del laboratorio:

```bash
aws elbv2 describe-load-balancers \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?VpcId=='${LAB_VPC_ID}'].{Arn:LoadBalancerArn,Estado:State.Code}" \
  --output table

aws elbv2 describe-target-groups \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "TargetGroups[?VpcId=='${LAB_VPC_ID}'].{Arn:TargetGroupArn,Tipo:TargetType}" \
  --output table

aws ec2 describe-nat-gateways \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --filter "Name=vpc-id,Values=${LAB_VPC_ID}" \
  --query 'NatGateways[].{Id:NatGatewayId,Estado:State}' \
  --output table

aws ec2 describe-network-interfaces \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${LAB_VPC_ID}" \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Estado:Status,Descripcion:Description}' \
  --output table

aws ec2 describe-security-groups \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${LAB_VPC_ID}" \
  --query 'SecurityGroups[].{Id:GroupId,Nombre:GroupName}' \
  --output table
```

Todas esas salidas deben estar vacías. Finalmente, comprobar la VPC debe devolver `InvalidVpcID.NotFound`:

```bash
aws ec2 describe-vpcs \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --vpc-ids "$LAB_VPC_ID"
```

`AccessDenied` no demuestra ausencia. Una salida vacía en los inventarios tampoco es prueba absoluta: EBS, snapshots y
Elastic IP no se identifican siempre por VPC. Búscalos también en el inventario por tags, contrasta el inventario previo
y revisa recursos `available` o sin adjuntar creados durante el ejercicio. No elimines un recurso solo porque contiene
el nombre del clúster.

### 3. Logs y recursos con ciclo de vida independiente

```bash
aws logs describe-log-groups \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}/cluster" \
  --query 'logGroups[].{Nombre:logGroupName,Retencion:retentionInDays,Bytes:storedBytes}' \
  --output table
```

Si un log group permanece, decide si la evidencia debe conservarse o eliminarse según la política. Haz la misma revisión
en EC2/EBS, Elastic Load Balancing, VPC, CloudWatch, Route 53, ACM, ECR, AWS Backup y servicios instalados durante el
ejercicio. En Auto Mode, revisa expresamente volúmenes EBS: pueden sobrevivir al clúster.

## Criterio de salida

- EKS devuelve `ResourceNotFoundException` con credenciales válidas.
- No hay stacks del laboratorio en un estado distinto de `DELETE_COMPLETE`.
- No quedan ALB/NLB, target groups, NAT Gateways, Elastic IP, ENI o security groups del laboratorio.
- EBS/PV/snapshots tienen una decisión explícita de conservar o eliminar.
- Logs y backups tienen retención aprobada.
- El inventario por tags fue revisado en la misma cuenta y región.
- El propietario comprobará Cost Explorer/Billing cuando los datos estén disponibles.

## Fuentes oficiales

- [Precios de Amazon EKS](https://aws.amazon.com/eks/pricing/)
- [Eliminar un clúster EKS](https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html)
- [Eliminar clústeres con `eksctl`](https://docs.aws.amazon.com/eks/latest/eksctl/creating-and-managing-clusters.html)
- [Deletion protection](https://docs.aws.amazon.com/eks/latest/userguide/deletion-protection.html)
- [Optimización de costos de EKS](https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt.html)

[← Solución de problemas](05-solucion-de-problemas.md) · [Referencia CLI →](referencia-cli.md)
