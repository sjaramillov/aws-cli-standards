# 3. Operación esencial

## Objetivo

Inspeccionar el clúster, desplegar una carga limitada, observar su estado y practicar un diagnóstico sin crear un
Load Balancer.

> [!IMPORTANT]
> Este capítulo presupone el clúster dedicado creado en la opción B del capítulo anterior. En un clúster compartido,
> `learning-ng`, autenticación `API`, permisos globales y el namespace `eks-learning` pueden no existir o no
> pertenecerte. Usa únicamente el namespace y las acciones que su propietario te haya asignado.

## 1. Verificar el objetivo antes de escribir

En una nueva terminal, sustituye la ruta por la ubicación real del clon y vuelve a definir las variables del laboratorio
y el kubeconfig aislado:

```bash
cd "/ruta/completa/aws-cli-standards"

export AWS_PROFILE="mi-sandbox"
export AWS_REGION="us-east-1"
export CLUSTER_NAME="eks-learning"
export EXPECTED_AWS_ACCOUNT_ID="123456789012"
export OWNER_TAG="mi-usuario"
export AWS_PAGER=""
export KUBECONFIG="$PWD/.kubeconfig.${CLUSTER_NAME}"

EKS_VERSION="$(aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.version' \
  --output text)" &&
export EKS_VERSION &&

./scripts/preflight.sh &&
./scripts/verify-lab-ownership.sh &&
kubectl config current-context &&
kubectl cluster-info
```

No continúes si la cuenta, región o contexto no coinciden.

## 2. Inspeccionar EKS desde AWS

Estos comandos son de solo lectura:

```bash
aws eks describe-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Estado:status,Version:version,Plataforma:platformVersion,Auth:accessConfig.authenticationMode,EndpointPublico:resourcesVpcConfig.endpointPublicAccess,EndpointPrivado:resourcesVpcConfig.endpointPrivateAccess,CIDRs:resourcesVpcConfig.publicAccessCidrs,Problemas:health.issues}' \
  --output yaml

aws eks describe-nodegroup \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name learning-ng \
  --query 'nodegroup.{Estado:status,AMI:amiType,Capacidad:capacityType,Tipos:instanceTypes,Escalado:scalingConfig,Problemas:health.issues}' \
  --output yaml
```

Comprueba que la versión es la esperada, la autenticación usa `API`, el acceso privado está habilitado y el CIDR
público no es abierto a todo Internet.

## 3. Inspeccionar Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
kubectl auth whoami
kubectl auth can-i create deployments --namespace eks-learning
```

`kubectl auth whoami` requiere una versión reciente de Kubernetes. Si no está disponible, conserva como evidencia el
ARN de `aws sts get-caller-identity` y usa `kubectl auth can-i` para probar autorización.

## 4. Validar y desplegar la aplicación

El manifiesto usa un namespace con Pod Security `restricted`, imagen por digest, usuario no root, `seccomp`,
capabilities eliminadas, token de ServiceAccount desactivado, probes y recursos limitados. Es un ejemplo educativo, no
una aplicación de producción.

Primero valida sin persistir cambios:

```bash
kubectl apply --dry-run=client -f examples/workloads/hello.yaml
```

Después aplica y espera una condición observable:

```bash
./scripts/verify-lab-ownership.sh &&
kubectl apply -f examples/workloads/hello.yaml &&
kubectl rollout status deployment/hello --namespace eks-learning --timeout=5m &&
kubectl get all --namespace eks-learning
```

La salida esperada contiene un Deployment `1/1`, un Pod `Running` y un Service `ClusterIP`. Si el Pod no inicia:

```bash
kubectl describe pod --namespace eks-learning --selector app.kubernetes.io/name=hello
kubectl get events --namespace eks-learning --sort-by='.lastTimestamp'
kubectl logs deployment/hello --namespace eks-learning --tail=100
```

## 5. Probar sin un Load Balancer

En una terminal deja el túnel activo:

```bash
kubectl port-forward --namespace eks-learning service/hello 8080:80
```

En otra terminal:

```bash
curl --fail --show-error http://127.0.0.1:8080/
```

La respuesta debe contener el hostname de un Pod. `port-forward` es local y temporal; no crea ALB, NLB, DNS ni una
dirección pública.

## 6. Ejercicio opcional de diagnóstico

Provoca un `ImagePullBackOff` únicamente en este namespace de laboratorio:

```bash
./scripts/verify-lab-ownership.sh &&
kubectl set image \
  deployment/hello \
  hello=registry.k8s.io/e2e-test-images/agnhost:no-existe \
  --namespace eks-learning

kubectl rollout status deployment/hello --namespace eks-learning --timeout=30s || true
kubectl get pods --namespace eks-learning
kubectl describe pod --namespace eks-learning --selector app.kubernetes.io/name=hello
```

Restaura el Deployment y verifica la recuperación:

```bash
./scripts/verify-lab-ownership.sh &&
kubectl rollout undo deployment/hello --namespace eks-learning &&
kubectl rollout status deployment/hello --namespace eks-learning --timeout=5m
```

El patrón de diagnóstico es `get` → `describe` → eventos → logs. No empieces eliminando recursos: primero conserva
evidencia.

## 7. Conocer los add-ons sin modificarlos

```bash
aws eks list-addons \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table

kubectl get daemonset aws-node --namespace kube-system
kubectl get deployment coredns --namespace kube-system
kubectl get daemonset kube-proxy --namespace kube-system
```

Un componente puede ser un EKS add-on o estar autogestionado. Antes de actualizarlo, identifica su tipo, versión,
configuración, permisos y compatibilidad. No uses `create-addon` con una versión inventada ni
`--resolve-conflicts OVERWRITE` sin revisar qué se perderá.

Para consultar compatibilidad de un add-on:

```bash
aws eks describe-addon-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --addon-name vpc-cni \
  --kubernetes-version "$EKS_VERSION" \
  --output table
```

## 8. Conservar el escenario para los capítulos siguientes

No elimines todavía `hello`: el capítulo de solución de problemas usa su Deployment y sus Pods para enseñar a reunir
evidencia. Continúa con seguridad y diagnóstico; al finalizar, el runbook de [costos y limpieza](06-costos-y-limpieza.md)
retira primero la carga y después el clúster. Si debes detenerte entre capítulos, recuerda que cerrar la terminal o
apagar tu equipo no detiene los cargos de AWS.

## Fuentes oficiales

- [Desplegar una aplicación de muestra en EKS](https://docs.aws.amazon.com/eks/latest/userguide/sample-deployment.html)
- [Buenas prácticas de seguridad de Pods](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html)
- [EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [Compatibilidad de add-ons](https://docs.aws.amazon.com/eks/latest/userguide/addon-compat.html)

[← Primer clúster](02-primer-cluster.md) · [Siguiente: seguridad →](04-seguridad.md)
