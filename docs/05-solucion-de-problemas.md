# 5. Solución de problemas

## Objetivo

Diagnosticar desde la capa correcta, conservar evidencia útil y evitar exponer credenciales o empeorar el incidente.

## Método: identidad → AWS → red → Kubernetes → workload

Empieza por la capa más externa y avanza solo cuando cada comprobación funciona:

1. **Identidad:** cuenta, rol, vigencia de sesión, región y reloj local.
2. **AWS:** estado de EKS, Managed Node Group, updates y CloudFormation.
3. **Red:** DNS, endpoint público/privado, CIDR permitido, VPN y rutas.
4. **Kubernetes:** contexto, autorización, nodo, componentes de `kube-system` y eventos.
5. **Workload:** scheduling, imagen, probes, configuración y logs.

Eliminar o recrear antes de entender la falla suele borrar evidencia y puede dejar recursos facturables.

## Paquete de diagnóstico de solo lectura

Ejecuta por partes y revisa antes de compartir. IDs de cuenta, ARNs, endpoints, IPs y nombres internos pueden ser
sensibles para tu organización.

```bash
aws --version
kubectl version --client
eksctl version

aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --query '{Account:Account,Arn:Arn}' \
  --output yaml

aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Estado:status,Version:version,Plataforma:platformVersion,Salud:health.issues,Red:resourcesVpcConfig,Acceso:accessConfig}' \
  --output yaml

aws eks list-updates \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --output table

kubectl config current-context
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

No compartas `~/.aws`, kubeconfigs completos, `aws configure list`, tokens, variables de entorno, Secrets ni la salida
de `kubectl get secret -o yaml`.

## Errores frecuentes

### `ExpiredToken`, `InvalidClientTokenId` o sesión SSO vencida

Comprueba el perfil y renueva la sesión:

```bash
aws sso login --profile "$AWS_PROFILE"
./scripts/preflight.sh
```

No “soluciones” la expiración creando una access key permanente.

### `AccessDenied`

Conserva el servicio, acción, recurso y ARN del principal que aparecen en el error. Verifica primero que la cuenta y el
rol sean correctos. En una organización también pueden intervenir SCP, permission boundary, session policy o resource
policy. Solicita únicamente la acción necesaria y vuelve a probar.

### EKS devuelve `ResourceNotFoundException`

Los clústeres son regionales. Lista en la región explícita:

```bash
aws eks list-clusters \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --output table
```

Comprueba ortografía y cuenta. No asumas que el recurso fue eliminado hasta obtener el error con una sesión válida.

### `kubectl`: `Unauthorized`

1. verifica que la sesión AWS no expiró;
2. regenera el kubeconfig con perfil, región, nombre y alias explícitos;
3. confirma qué rol usa la entrada `exec`;
4. comprueba que existe una Access Entry para el principal correspondiente.

```bash
aws eks list-access-entries \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table
```

No edites `aws-auth` por reflejo en un clúster con autenticación `API`.

### `kubectl`: `Forbidden`

La autenticación probablemente funcionó, pero la autorización denegó la acción. Prueba exactamente el verbo, recurso y
namespace:

```bash
kubectl auth can-i create deployments --namespace eks-learning
kubectl auth can-i get secrets --namespace eks-learning
```

Revisa access policies, grupos de la Access Entry, `Role`, `ClusterRole` y bindings. No conviertas todo en
`cluster-admin` para ocultar el problema.

### Timeout al API server

Revisa `endpointPublicAccess`, `endpointPrivateAccess` y `publicAccessCidrs` en `describe-cluster`. Causas comunes:

- cambió la IP de salida o la VPN;
- el endpoint es privado y no existe ruta/DNS desde tu red;
- un proxy o firewall bloquea 443;
- los nodos no pueden resolver o alcanzar el endpoint.

Si actualizas CIDRs, conserva acceso privado para los nodos y espera a que la actualización termine. Nunca abras el
endpoint globalmente como arreglo permanente.

### La creación falló antes de obtener un clúster utilizable

No repitas `create` ni borres stacks por coincidencia de nombre. Conserva la salida de `eksctl` y haz primero un
inventario de solo lectura en la cuenta y región esperadas:

```bash
./scripts/preflight.sh &&
aws cloudformation list-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "StackSummaries[?starts_with(StackName, 'eksctl-${CLUSTER_NAME}-') && StackStatus!='DELETE_COMPLETE'].{Nombre:StackName,Estado:StackStatus,Id:StackId}" \
  --output table
```

El guard de limpieza normal fallará si todavía no existen un endpoint, kubeconfig, tags y stack estable; es una barrera
intencional. Revisa los eventos de cada stack exacto, confirma cuenta, región, ARN y etiquetas con el propietario de la
cuenta, y usa su procedimiento aprobado para recuperar o retirar la creación parcial. No omitas el guard ni conviertas
un nombre parecido en autorización para borrar.

### Managed Node Group en `CREATE_FAILED` o nodos ausentes

Consulta salud y eventos de CloudFormation:

```bash
aws eks describe-nodegroup \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name learning-ng \
  --query 'nodegroup.{Estado:status,Problemas:health.issues,Recursos:resources}' \
  --output yaml

aws cloudformation describe-stack-events \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "eksctl-${CLUSTER_NAME}-nodegroup-learning-ng" \
  --max-items 30 \
  --query 'StackEvents[].{Hora:Timestamp,Estado:ResourceStatus,Tipo:ResourceType,Motivo:ResourceStatusReason}' \
  --output table
```

Revisa cuota/stock del tipo de instancia, roles, subredes, IP pública en el laboratorio, security groups y acceso al API
server. Un clúster `ACTIVE` no implica que el node group haya terminado.

### Pod `Pending`

```bash
kubectl describe pod --namespace eks-learning --selector app.kubernetes.io/name=hello
kubectl get events --namespace eks-learning --sort-by='.lastTimestamp'
kubectl describe node
```

Busca recursos insuficientes, taints, selectors, PVC, límites de IP del VPC CNI o ausencia de nodos. No aumentes el
número/tamaño de nodos sin comprender qué pide el scheduler.

### `ImagePullBackOff`

En `describe pod`, distingue imagen inexistente, arquitectura no soportada, rate limit, DNS/egress o autenticación a
ECR. Comprueba repositorio, tag/digest y permisos. No añadas credenciales de registry en texto plano.

### `CrashLoopBackOff` o probes fallidas

```bash
kubectl logs deployment/hello --namespace eks-learning --tail=100
kubectl logs deployment/hello --namespace eks-learning --previous --tail=100
kubectl describe deployment hello --namespace eks-learning
```

La segunda llamada muestra el contenedor anterior. Revisa exit code, OOM, configuración, puerto y tiempos de probes.

### La eliminación falla

Busca stacks `DELETE_FAILED` y sus eventos. Causas comunes: Services/Ingress con balanceadores, security groups o ENI en
uso, PDB que impide drenar nodos, PVC/PV, deletion protection, Fargate profiles o EKS capabilities. Sigue el orden de
[costos y limpieza](06-costos-y-limpieza.md); no borres manualmente una VPC completa sin resolver dependencias.

## Escalamiento útil

Un reporte reproducible incluye:

- hora y zona horaria;
- cuenta/ARN redactados de forma consistente y región;
- versión de las tres herramientas;
- comando exacto y código de salida;
- estado de EKS/Node Group/update;
- eventos relevantes en orden temporal;
- cambio más reciente y resultado esperado;
- qué se probó y qué no se modificó.

## Fuentes oficiales

- [Troubleshooting de Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Crear kubeconfig](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html)
- [Acceso con EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [Endpoint del API server](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html)

[← Seguridad](04-seguridad.md) · [Siguiente: costos y limpieza →](06-costos-y-limpieza.md)
