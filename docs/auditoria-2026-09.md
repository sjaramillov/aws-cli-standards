# Auditoría técnica y editorial — 2026-09-02

## Alcance y método

Se auditó `main` en el commit `7e03c2c347def0bfaa8152cf0744bef45470d381`. La línea base tenía un único
`README.md` de 224 líneas, sin tests, licencia ni archivos de contribución/seguridad.

La revisión cubrió:

- exactitud contra documentación oficial de AWS/EKS vigente al 2026-09-02;
- seguridad de comandos y riesgo de operar en cuenta/región equivocada;
- reproducibilidad, prerrequisitos, estados asíncronos y limpieza;
- costos, ciclo de soporte, identidad, red, add-ons y operación;
- progresión pedagógica para principiantes;
- enlaces, estructura Markdown, accesibilidad y gobierno del repositorio.

No se creó un clúster real: hacerlo habría requerido credenciales, permisos y costos del usuario. Los comandos se
contrastaron con referencias oficiales y las validaciones locales se describen en
[limitaciones](#limitaciones-de-verificación).

## Veredicto de la línea base

El contenido original era un buen inventario inicial de temas —IaC, GitOps, redes privadas, observabilidad, secretos,
RACI y policy-as-code—, pero no era todavía una guía ejecutable y segura para principiantes ni un estándar empresarial
verificable. Mezclaba introducción, *cheatsheet* y plantilla enterprise, y su primer camino de creación ya no funcionaba
con EKS actual.

## Hallazgos y remediaciones

| ID | Severidad | Hallazgo en `7e03c2c` | Riesgo | Remediación implementada |
| --- | --- | --- | --- | --- |
| A-01 | Crítica | `--version 1.29` estaba fijado | La versión ya no se ofrece en EKS | Descubrimiento dinámico y validación `STANDARD_SUPPORT` |
| A-02 | Crítica | `--ami-type AL2_x86_64` | AMIs EKS AL2 sin publicación desde 2025; AL2 llegó a EOS | Laboratorio AL2023 y explicación de Bottlerocket |
| A-03 | Crítica | `delete-cluster` aparecía aislado | Fallo por dependencias y recursos/costos huérfanos | Runbook ordenado con `eksctl --wait` y verificación posterior |
| A-04 | Alta | Comandos sin perfil, región ni preflight | Cambios en account/región equivocados | Variables explícitas, account esperado y script de solo lectura |
| A-05 | Alta | Placeholders como `<cluster-name>` | El shell puede interpretarlos como redirecciones | Variables inicializadas, validadas y entrecomilladas |
| A-06 | Alta | `aws eks create-cluster` se presentaba como inicio completo | Requiere red/roles y solo crea control plane | Flujo reproducible con `eksctl`, plan `--dry-run` y waiters |
| A-07 | Alta | Sin costos ni presupuesto previo | Facturación inesperada de EKS/EC2/NAT/ELB/EBS/logs | Advertencia previa, topología de lab sin NAT/LB y capítulo FinOps |
| A-08 | Alta | API restringida se declaraba, pero el comando dejaba defaults | Endpoint público podía aceptar cualquier CIDR | Endpoint privado + público limitado por CIDR en plantilla |
| A-09 | Alta | IRSA era la única identidad de Pods | Omitía la recomendación actual y casos de compatibilidad | Pod Identity primero; IRSA como alternativa documentada |
| A-10 | Alta | No había Access Entries ni distinción IAM/RBAC | Modelo de acceso incompleto y heredado | Autenticación `API`, conceptos, inventario y ejemplo namespace-scoped |
| A-11 | Alta | Crear `vpc-cni` con `<version>` sin descubrimiento | Conflictos, incompatibilidad o permisos incorrectos | Flujo de inspección/compatibilidad antes de cualquier update |
| A-12 | Alta | `update-kubeconfig --role-arn` se explicaba ambiguamente | Contexto/rol equivocado y modificación global | Kubeconfig aislado, `--dry-run`, alias y diferencia con assume-role |
| A-13 | Media | Diagramas generados contenían relaciones erróneas | Enseñaban almacenamiento/runtime/arquitectura incorrectos | Diagramas Mermaid pequeños, revisables y versionados |
| A-14 | Media | Diagrama VMware/NSX-T descrito como blueprint hub-and-spoke | Patrón específico presentado como regla Well-Architected | Matriz de decisiones y arquitectura conceptual neutral |
| A-15 | Media | “Subnets públicas solo para ALB/NLB” | Ignoraba Load Balancers internos en privadas | Distinción explícita internet-facing/interno |
| A-16 | Media | “Karpenter / AutoScaling” mezclaba mecanismos | Confusión de ownership y escalado | Comparación MNG, Auto Mode, Fargate y Karpenter |
| A-17 | Media | “Todos los despliegues son auditados” sin policies/tests | Afirmación de compliance sin evidencia | Catálogo control→mecanismo→evidencia→owner→frecuencia |
| A-18 | Media | `MustRunAsNonRoot` y controles sin manifiesto | Terminología heredada y no verificable | PSA `restricted` y workload no-root fijado por digest |
| A-19 | Media | Cuatro enlaces placeholder y dos etiquetas de imagen vacías | Navegación rota y mala accesibilidad | Estructura modular y comprobación automática de enlaces internos |
| A-20 | Media | Mezcla de inglés/español y jerarquía Markdown rota | Alta carga cognitiva | Español consistente, un H1 por archivo y ruta numerada |
| A-21 | Media | “Interno” en un repo público y fechas contradictorias | Riesgo de gobierno y falta de trazabilidad | Plantilla pública con clasificación/estado/revisión explícitos |
| A-22 | Media | Sin troubleshooting, outputs ni criterios de éxito | El alumno no podía saber si avanzaba | Checkpoints, salidas esperadas y método diagnóstico |
| A-23 | Media | Sin CI ni política de mantenimiento | Regresión y nueva obsolescencia | Checks internos, enlaces externos y Dependabot para Actions |
| A-24 | Baja | Sin CONTRIBUTING, SECURITY ni CODEOWNERS | Colaboración y reporte ambiguos | Archivos de gobierno y plantillas de PR/issues |
| A-25 | Media | Sin licencia | Reutilización legalmente ambigua | Licencia MIT añadida por decisión del propietario |

## Decisiones pedagógicas

### Managed Node Groups antes de Auto Mode

El laboratorio principal usa un Managed Node Group para que el alumno observe EC2, AMI, capacidad y ciclo de upgrade.
EKS Auto Mode se documenta como una alternativa actual de primera clase, pero aprender solo con sus abstracciones
ocultaría conceptos que la guía pretende enseñar. Una organización puede invertir el orden si prioriza tiempo al primer
despliegue sobre comprensión del plano de datos.

### Topología económica, no productiva

El laboratorio usa un nodo público sin SSH, endpoint privado, acceso público limitado y NAT deshabilitado. Esta decisión
reduce costos y evita el NAT Gateway por hora, pero sacrifica aislamiento y alta disponibilidad. El documento lo marca
como desviación educativa; la plantilla enterprise exige evaluar nodos privados, múltiples AZ y egress controlado.

### `ClusterIP` antes de Load Balancer

La primera aplicación se accede mediante `port-forward`. Así el alumno aprende Deployment/Pod/Service sin aprovisionar
un ALB/NLB, DNS o certificado y sin riesgo de dejarlos cobrando.

### Versiones descubiertas, no “actualizadas” a mano

El corte de auditoría confirmó versiones concretas, pero no se trasladaron como un default permanente. La guía consulta
`describe-cluster-versions` y exige `STANDARD_SUPPORT`, reduciendo la próxima fecha de obsolescencia.

## Limitaciones de verificación

- La plantilla renderizada se validó contra el JSON Schema incluido en `eksctl` 0.230.0. El manifiesto pasó
  `kubeconform` 0.8.0 en modo estricto contra Kubernetes 1.34, 1.35 y 1.36. CI descarga los binarios fijados y comprueba
  sus SHA-256 antes de usarlos; los schemas Kubernetes se fijan a un commit explícito.
- Los scripts pasaron ShellCheck 0.11.0 y los workflows pasaron `actionlint` 1.7.12. Mermaid se revisó como código, pero
  no se renderiza automáticamente en CI.
- Las dependencias Python directas y transitivas quedaron bloqueadas con hashes; los binarios externos usados por CI se
  descargan en versiones fijas y se verifican antes de ejecutar.
- El preflight y el guard de propiedad tienen pruebas sin red que simulan cuenta equivocada, usuario raíz, versión fuera
  de soporte, clientes incompatibles, credenciales de entorno conflictivas, tags alterados, ARN de otra cuenta, endpoint
  de kubeconfig ajeno y stack eliminado o inestable.
- El `--dry-run` completo de `eksctl` consulta STS y se dejó como paso del usuario para no acceder a una cuenta AWS sin
  autorización explícita.
- No se ejecutó creación, upgrade o borrado contra una cuenta AWS.
- No se verificó capacidad EC2 regional ni SCP/quotas de una organización concreta.
- La validación de schema Kubernetes no cubre toda la lógica de admisión; `dry-run=server` y rollout requieren un
  clúster autorizado.
- La imagen de ejemplo se verificó en `registry.k8s.io` y se fijó por digest multi-arquitectura; debe seguir escaneándose.
- Lychee 0.24.2 verificó 119 referencias Markdown (70 destinos únicos, con localhost excluido) sin errores el
  2026-09-02; pueden comportarse distinto desde GitHub Actions y el workflow tiene reintentos.
- El check local busca formatos comunes de credenciales en los archivos de texto actuales; no sustituye un escaneo del
  historial ni detección de secretos del proveedor Git.
- GitHub security features, rulesets y private vulnerability reporting dependen del plan/configuración del repositorio y
  no se activan desde cambios de archivos.

## Decisiones pendientes del propietario

1. Activar branch/ruleset para exigir pull request y el check `docs-quality` en `main`.
2. Activar secret scanning, push protection y private vulnerability reporting si están disponibles.
3. Definir contacto privado de seguridad y SLA de respuesta.
4. Decidir si el repositorio seguirá siendo una guía educativa o incluirá implementaciones IaC productivas separadas.
5. Ejecutar el laboratorio en una cuenta desechable, registrar tiempos/costos reales y probarlo con personas nuevas.

## Criterio de mantenimiento

Revisar al menos trimestralmente y ante anuncios de EKS:

- versiones y fechas de soporte;
- AWS CLI, `eksctl` y compatibilidad de `kubectl`;
- AMIs, tipos de cómputo y defaults;
- Access Entries, Pod Identity, add-ons y upgrade/rollback;
- pricing y semántica de eliminación;
- enlaces, workflow y hashes de Actions.

Todo cambio técnico debe citar una fuente primaria y actualizar la fecha de revisión solo después de ejecutar los checks
y registrar qué se verificó.

## Fuentes primarias principales

- [Ciclo de versiones de EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Fin de las AMIs EKS basadas en AL2](https://docs.aws.amazon.com/eks/latest/userguide/eks-ami-deprecation-faqs.html)
- [Crear un clúster EKS](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [EKS Pod Identity e IRSA](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html)
- [Eliminar un clúster](https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html)
- [Precios de EKS](https://aws.amazon.com/eks/pricing/)

[← Volver al README](../README.md)
