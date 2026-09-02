# 4. Seguridad base

## Objetivo

Entender los controles mínimos y la evidencia que deberías exigir antes de llamar “seguro” a un clúster EKS.
Configurar un producto completo queda fuera del laboratorio; este capítulo distingue prácticas actuales de afirmaciones
aspiracionales.

## Responsabilidad compartida

AWS opera y parchea el plano de control administrado. El cliente sigue decidiendo y operando, entre otros:

- identidades IAM y autorización Kubernetes;
- endpoint, VPC, egress, DNS y políticas de red;
- nodos cuando no usa una modalidad que los abstrae;
- imágenes, configuración, secretos y datos de las aplicaciones;
- observabilidad, detección, respuesta, backups y actualizaciones;
- validación de controles de cumplimiento.

Un servicio administrado reduce trabajo indiferenciado; no elimina estas decisiones.

## Línea base priorizada

| Área | Práctica recomendada | Evidencia mínima |
| --- | --- | --- |
| Personas | Federación/IAM Identity Center, MFA y roles temporales | ARN de rol, sesión temporal y revisión de permisos |
| Acceso EKS | Access Entries; RBAC o access policies con alcance mínimo | Inventario de entradas y pruebas `kubectl auth can-i` |
| Workloads | EKS Pod Identity cuando sea compatible; IRSA cuando no | Asociación ServiceAccount↔rol y policy mínima |
| API server | Endpoint privado y público deshabilitado o restringido | `resourcesVpcConfig` y prueba desde red autorizada/no autorizada |
| Auditoría | CloudTrail y logs EKS `audit`/`authenticator` con retención | Log groups, retención, alarmas y consultas de prueba |
| Pods | Pod Security Admission, no-root, seccomp y capabilities mínimas | Manifiestos y prueba de rechazo de un Pod inseguro |
| Red de Pods | NetworkPolicy con un motor realmente habilitado | Política default-deny y prueba de conectividad negativa |
| Secretos | Nada sensible en Git; Secrets Manager u otro almacén aprobado | Escaneo, rotación y acceso mínimo por workload |
| Imágenes | Registro aprobado, digest, escaneo y procedencia | Digest desplegado y resultado de escaneo/admisión |
| Nodos | AL2023/Bottlerocket, IMDSv2, sin SSH rutinario, parches | AMI, launch template y fecha de actualización |
| Ciclo de vida | Versiones en soporte estándar y upgrades ensayados | Upgrade Insights, plan, pruebas y rollback |

## Acceso de personas: IAM, Access Entries y RBAC

Para un clúster nuevo, usa modo de autenticación `API`. `API_AND_CONFIG_MAP` es útil para migrar desde `aws-auth`,
pero conservar dos fuentes de acceso aumenta la complejidad. No se puede volver a un modo que elimine la API de Access
Entries después de habilitarla.

Inspecciona el laboratorio:

```bash
aws eks list-access-entries \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table
```

Para cada identidad humana:

- prefiere un rol, no un IAM user;
- separa administración, operación y lectura;
- limita por namespace cuando el caso lo permita;
- prueba permisos permitidos **y** denegados;
- revisa periódicamente y elimina accesos sin uso;
- conserva una ruta de recuperación controlada, no credenciales compartidas.

Las access policies administradas por EKS simplifican casos comunes, pero no sustituyen una revisión de su alcance.
Algunas políticas de vista administrativa pueden leer Kubernetes Secrets. Para permisos propios, asocia la Access Entry
con grupos Kubernetes y define RBAC revisable en Git.

## Identidad de workloads

No guardes access keys en `Secret`, variables de entorno, imágenes ni repositorios. Asocia un ServiceAccount a un rol
de mínimo privilegio:

- **EKS Pod Identity:** primera opción cuando el tipo de nodo y el SDK son compatibles; requiere el Pod Identity Agent
  en EKS estándar y ya está integrado en Auto Mode.
- **IRSA:** opción válida cuando ya existe ese patrón o cuando Pod Identity no soporta el entorno, como determinados
  Pods Fargate o Windows.

Inventario de Pod Identity:

```bash
aws eks list-pod-identity-associations \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --output table
```

Restringe el acceso de Pods al Instance Metadata Service. IMDSv2 evita solicitudes sin token, pero no convierte el rol
del nodo en una identidad apropiada para aplicaciones. La plantilla bloquea IMDS para Pods ordinarios; los Pods con
`hostNetwork: true` siempre conservan acceso y requieren revisión adicional.

## Endpoint y red

El endpoint público de EKS requiere autenticación aun cuando permita `0.0.0.0/0`, pero esa configuración amplía la
superficie de red. Para producción, habilita acceso privado y deshabilita el público cuando exista conectividad privada;
si necesitas acceso público, limítalo a CIDRs conocidos.

No hay una regla universal que diga “Load Balancers solo en subredes públicas”. Un balanceador *internet-facing* usa
subredes públicas; uno interno usa subredes privadas. Etiqueta las subredes y decide el esquema de forma explícita.

Crear objetos `NetworkPolicy` no garantiza su aplicación. En EKS estándar, la función de Network Policy del VPC CNI
no viene habilitada por defecto. Define el motor —VPC CNI, Cilium, Calico u otro—, sus límites y una prueba negativa de
tráfico antes de declarar el control efectivo.

## Pods y admisión

El manifiesto [hello.yaml](../examples/workloads/hello.yaml) ilustra un Pod Security Standard `restricted`. En una
plataforma real:

1. inventaría incompatibilidades;
2. empieza con `audit` y `warn`;
3. corrige workloads;
4. activa `enforce` por namespace;
5. documenta excepciones, propietario y fecha de caducidad.

Gatekeeper o Kyverno pueden expresar políticas adicionales, pero “instalado” no equivale a “todos los despliegues
están auditados”. Cada control necesita política versionada, modo, prueba, evidencia, responsable y tratamiento de
excepciones.

Los `requests` son esenciales para scheduling y capacidad. Los límites de memoria suelen prevenir consumo sin cota;
los límites de CPU pueden causar throttling y deben responder al comportamiento del servicio, no a una regla ciega.

## Secretos y cifrado

En EKS 1.28 y posteriores, los datos de la API de Kubernetes tienen envelope encryption por defecto con una clave KMS
propiedad de AWS; puedes asociar una clave administrada por el cliente cuando los requisitos lo justifiquen. Esto no
cifra automáticamente EBS, imágenes, logs ni tráfico, y tampoco impide que un principal autorizado lea un Secret.

Para secretos de aplicaciones, usa AWS Secrets Manager u otro almacén aprobado, rotación y acceso por workload. No
publiques valores sensibles codificados en base64: base64 no es cifrado.

## Nodos e imágenes

AWS dejó de publicar AMIs EKS optimizadas basadas en AL2 el 26 de noviembre de 2025. Para clústeres actuales usa
AL2023, Bottlerocket u otra distribución soportada tras evaluar compatibilidad. AL2023 emplea `nodeadm` y cgroup v2;
prueba runtimes y aplicaciones antiguas, especialmente JVMs que no entienden cgroup v2.

Fija imágenes por digest en despliegues controlados, escanéalas y actualízalas de forma intencional. Un digest mejora
reproducibilidad, pero no garantiza que la imagen esté libre de vulnerabilidades.

## Logging, detección y respuesta

Los logs del plano de control están desactivados por defecto. Como mínimo evalúa `audit` y `authenticator`; para
diagnóstico completo considera también `api`, `controllerManager` y `scheduler`. Define retención para evitar costo
indefinido. CloudTrail registra llamadas a la API de AWS; el audit log de Kubernetes registra acciones en su API. Se
necesitan ambos para reconstruir un incidente.

No termines en “enviar logs”. Define consultas, alertas, responsables, reloj de retención, acceso a evidencia y un
ejercicio periódico de respuesta.

## Checklist de producción

- [ ] Cuentas separadas por entorno y guardrails organizacionales.
- [ ] Acceso humano federado, temporal y revisado.
- [ ] Access Entries y RBAC probados, sin dependencias ocultas de `aws-auth`.
- [ ] Endpoint y egress documentados; API pública no abierta globalmente.
- [ ] Workloads con Pod Identity/IRSA y roles mínimos.
- [ ] Políticas de admisión y red demostradas con pruebas negativas.
- [ ] Secretos externos, rotación y cifrado con alcance comprendido.
- [ ] Imágenes por digest, escaneadas y con procedencia verificable.
- [ ] Nodos soportados, parcheados y sin acceso administrativo cotidiano.
- [ ] Logs, métricas, trazas, detecciones y retención con presupuesto.
- [ ] Backups/restores y respuesta a incidentes ensayados.
- [ ] Versiones, add-ons y nodos dentro de una política de actualización.

## Fuentes oficiales

- [Buenas prácticas de seguridad de EKS](https://docs.aws.amazon.com/eks/latest/best-practices/security.html)
- [Administración de acceso al clúster](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-access-management.html)
- [Buenas prácticas de IAM para EKS](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)
- [EKS Pod Identity e IRSA](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html)
- [Seguridad de red](https://docs.aws.amazon.com/eks/latest/best-practices/network-security.html)
- [Cifrado por defecto de datos de la API](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
- [Logs del plano de control](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
- [Fin de soporte de AMIs AL2 para EKS](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)

[← Operación](03-operacion-esencial.md) · [Siguiente: solución de problemas →](05-solucion-de-problemas.md)
