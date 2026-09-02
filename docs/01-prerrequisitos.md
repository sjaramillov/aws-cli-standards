# 1. Prerrequisitos seguros

## Objetivo

Preparar herramientas, credenciales temporales, presupuesto y variables de contexto sin crear recursos de AWS.

## Antes de tocar la terminal

Necesitas:

- una cuenta *sandbox* separada de producción o autorización para usar un clúster existente;
- una identidad federada con MFA, preferiblemente mediante IAM Identity Center;
- permisos aprobados para EKS, CloudFormation, EC2, IAM y recursos relacionados si crearás el laboratorio;
- un presupuesto y una persona responsable de revisar los cargos;
- AWS CLI v2, `kubectl` y `eksctl` actualizados.

> [!CAUTION]
> No uses el usuario raíz de la cuenta. No crees access keys de larga duración para completar esta guía. En una
> organización, solicita un rol específico; no copies una política administrativa genérica a producción.

AWS Budgets genera alertas, pero no impide el gasto ni informa en tiempo real. Configúralo antes del laboratorio y
consulta la [guía oficial de creación de presupuestos](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html).

## 1. Preparar un entorno compatible

La ruta ejecutable está probada en macOS, Linux y WSL con Bash. Requiere `make`, Python 3, `sed`, `curl`, `date` y un
visor o editor de texto; `less` es el usado en los ejemplos. PowerShell nativo no está cubierto todavía.

```bash
command -v bash make python3 sed curl date less
```

## 2. Instalar las herramientas AWS y Kubernetes

Sigue los instaladores oficiales para tu sistema operativo:

- [Instalar o actualizar AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Instalar `kubectl`](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)
- [Instalar `eksctl`](https://docs.aws.amazon.com/eks/latest/eksctl/installation.html)

Comprueba qué binarios ejecutarás:

```bash
command -v aws kubectl eksctl
aws --version
kubectl version --client
eksctl version
```

`kubectl` debe estar como máximo a una versión *minor* de diferencia del plano de control. Vuelve a comprobarlo cuando
elijas la versión del clúster.

## 3. Configurar autenticación temporal

Si tu organización usa IAM Identity Center:

```bash
aws configure sso --profile mi-sandbox
aws sso login --profile mi-sandbox
```

No pegues credenciales en comandos, archivos del repositorio, capturas ni tickets. La AWS CLI guarda la configuración
de perfiles fuera de este proyecto.

Usa una terminal limpia. Variables como `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, web identity
o credenciales de contenedor pueden prevalecer sobre el perfil para herramientas basadas en AWS SDK. El preflight las
rechaza para impedir que AWS CLI valide una identidad y `eksctl` opere con otra; abre otra terminal o retira esas
variables del entorno sin copiar sus valores.

## 4. Fijar el contexto de trabajo

Sustituye estos valores y mantenlos en la misma terminal durante el laboratorio:

```bash
export AWS_PROFILE="mi-sandbox"
export AWS_REGION="us-east-1"
export CLUSTER_NAME="eks-learning"
export AWS_PAGER=""
```

Comprueba la identidad. Lee en voz alta la cuenta y el ARN antes de continuar:

```bash
aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --query '{Account:Account,Arn:Arn}' \
  --output table
```

Guarda el ID de la cuenta que **esperas** usar; no copies el de otra sesión:

```bash
export EXPECTED_AWS_ACCOUNT_ID="123456789012"
./scripts/preflight.sh
```

El script falla si la cuenta real no coincide. Es de solo lectura y nunca imprime secretos.

## 5. Elegir una versión con soporte estándar

No copies una versión desde una captura o un README antiguo. Consulta lo que EKS ofrece ahora:

```bash
aws eks describe-cluster-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --version-status STANDARD_SUPPORT \
  --query 'clusterVersions[].{Version:clusterVersion,Default:defaultVersion,FinEstandar:endOfStandardSupportDate}' \
  --output table
```

Elige una versión de la tabla y vuelve a comprobar su estado:

```bash
export EKS_VERSION="REEMPLAZA_X_Y"

aws eks describe-cluster-versions \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-versions "$EKS_VERSION" \
  --query 'clusterVersions[0].{Version:clusterVersion,Estado:versionStatus,FinEstandar:endOfStandardSupportDate}' \
  --output table
```

Continúa solo si `Estado` es `STANDARD_SUPPORT`. El soporte extendido cuesta más y no es una elección adecuada para un
laboratorio nuevo.

Ejecuta el control estricto que usarás antes de crear:

```bash
./scripts/preflight.sh --for-create
```

Sin `--for-create`, el script exige igualmente la cuenta esperada, pero permite inspeccionar o limpiar un clúster que
no esté en soporte estándar. El modo de creación exige `EKS_VERSION` y falla si su estado no es `STANDARD_SUPPORT`.

## 6. Confirmar permisos y límites

`eksctl` puede crear roles IAM, stacks de CloudFormation, una VPC y recursos EC2. En una cuenta organizacional, el rol
de laboratorio puede estar limitado por SCP, permission boundaries o cuotas. Confirma con el responsable de la cuenta:

- regiones permitidas;
- VPC, direcciones IPv4 y Availability Zones disponibles;
- posibilidad de crear y pasar roles IAM;
- límites de EKS, EC2 On-Demand y Elastic IP;
- política de etiquetas y fecha de expiración;
- quién puede retirar recursos si tu sesión falla.

No conviertas un `AccessDenied` en una razón para solicitar `AdministratorAccess` sin analizar la acción denegada.

## Matriz de verificación de esta revisión

| Componente | Verificado el 2026-09-02 |
| --- | --- |
| AWS CLI | Ayuda y parámetros con v2.36.30 |
| `eksctl` | ClusterConfig contra el schema incluido en v0.230.0 |
| Kubernetes | Manifiesto contra schemas estrictos 1.34, 1.35 y 1.36 |
| Shell/CI | Bash, ShellCheck 0.11.0 y `actionlint` 1.7.12 |

`preflight.sh --for-create` exige `eksctl` 0.230.0 o posterior y comprueba que `kubectl` esté como máximo a una minor
de la versión EKS elegida. La tabla es evidencia del corte, no una promesa de compatibilidad futura.

## Criterio de salida

No avances hasta que:

- los tres binarios respondan;
- `EXPECTED_AWS_ACCOUNT_ID` coincida con la sesión;
- la región sea intencional;
- `EKS_VERSION` esté en soporte estándar;
- exista un presupuesto/alerta y un procedimiento de limpieza;
- la cuenta no sea producción.

## Fuentes oficiales

- [Autenticación de AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html)
- [Orden de credenciales en AWS SDK for Go v2](https://docs.aws.amazon.com/sdk-for-go/v2/developer-guide/configure-gosdk.html)
- [Buenas prácticas de IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Instalación y compatibilidad de `kubectl`](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)
- [Versiones de Kubernetes en EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Cuotas de servicio de EKS](https://docs.aws.amazon.com/general/latest/gr/eks.html)

[← Conceptos](00-conceptos.md) · [Siguiente: primer clúster →](02-primer-cluster.md)
