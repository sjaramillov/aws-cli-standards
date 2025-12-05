# aws-cli-standards
aws cli standards for enterprise cloud adoption

<img width="638" height="891" alt="Screenshot 2025-12-04 at 10 16 51 PM" src="https://github.com/user-attachments/assets/20bc4170-40ec-4cc7-84c0-b79df65df472" />

# AWS EKS Enterprise Standard: [Nombre del Clúster/Proyecto]

| Control de Documento | Detalle |
| :--- | :--- |
| **ID del Documento** | REF-EKS-001 |
| **Versión** | 1.0.0 (Draft) |
| **Clasificación** | Interno / Confidencial |
| **Propietario Técnico** | Platform Engineering Team |
| **Estado** | Activo |
| **Última Actualización** | 2024-05-23 |

---

## 1. Propósito y Alcance

Este documento define la arquitectura de referencia, los patrones de operación y los controles de seguridad para el despliegue de cargas de trabajo en el clúster **[Nombre del Clúster]** basado en Amazon EKS. Su objetivo es garantizar la consistencia, la observabilidad y el cumplimiento normativo (Compliance) de todas las aplicaciones desplegadas.

### 1.1 Principios de Diseño
* **Inmutabilidad:** La infraestructura se gestiona como código (IaC) mediante Terraform/Crossplane.
* **GitOps:** Todo cambio en las cargas de trabajo debe pasar por un flujo de PR en Git (ArgoCD/Flux).
* **Segregación:** Aislamiento estricto de redes y roles (IAM Roles for Service Accounts - IRSA).

---

## 2. Arquitectura de Referencia (EKS Blueprint)

La arquitectura sigue el patrón **"Hub-and-Spoke"** alineado con el *AWS Well-Architected Framework*.



### 2.1 Componentes del Blueprint
1.  **Capa de Red (VPC):**
    * **Subnets Privadas (App Layer):** Donde residen los Worker Nodes. Sin acceso directo a Internet.
    * **Subnets Públicas (Ingress Layer):** Solo para Load Balancers (ALB/NLB) y NAT Gateways.
    * **Control Plane:** Gestionado por AWS, acceso al API Server restringido vía VPN/Bastion.

2.  **Cómputo (Data Plane):**
    * **Managed Node Groups:** Para cargas de trabajo base y de sistema (CoreDNS, CNI).
    * **Karpenter / AutoScaling:** Provisionamiento dinámico de nodos (Spot/On-Demand) basado en la demanda de los pods.
    * **Fargate Profiles:** Para tareas *serverless* o *batch jobs* aislados.

3.  **Ingress & Networking:**
    * **AWS Load Balancer Controller:** Gestiona ALBs para HTTP/HTTPS y NLBs para TCP.
    * **External DNS:** Sincronización automática de registros Route53.
    * **Service Mesh (Opcional):** Istio/Linkerd para mTLS y observabilidad avanzada.

---

## 3. Patrones de Operación

### 3.1 Modelo de Despliegue (GitOps)
No se permite el uso de `kubectl apply` manual en entornos productivos.

* **Herramienta:** ArgoCD / Flux.
* **Repositorio de Configuración:** `[git-repo-url]/k8s-manifests`
* **Estrategia de Sync:** Automated Prune / Self-Heal.

### 3.2 Observabilidad (O11y)
Stack estandarizado pre-instalado en todos los clústeres:
* **Métricas:** Prometheus (AMP) + Grafana.
* **Logs:** Fluentbit -> CloudWatch Logs / OpenSearch.
* **Tracing:** AWS X-Ray / Jaeger.

### 3.3 Gestión de Secretos
* **Prohibido:** Secretos en texto plano en repositorios Git.
* **Estándar:** External Secrets Operator (ESO) integrando con **AWS Secrets Manager**.

---

## 4. Matriz de Responsabilidades (RACI)

Definición clara de *quién hace qué* en la operación del clúster.

| Actividad | Platform Team | App/Dev Team | SecOps |
| :--- | :---: | :---: | :---: |
| **Provisionamiento del Clúster (EKS Upgrade)** | **R/A** | I | C |
| **Gestión de Nodos (Capacity Planning)** | **R/A** | I | I |
| **Creación de Namespaces y Quotas** | **R** | C | I |
| **Despliegue de Aplicaciones (Helm/Manifests)** | C | **R/A** | I |
| **Definición de Network Policies** | C | **R** | A |
| **Gestión de Secretos (Secrets Manager)** | I | **R** | A |
| **Respuesta a Incidentes (App Level)** | C | **R/A** | I |
| **Respuesta a Incidentes (Infra Level)** | **R/A** | I | C |

> **R:** Responsible, **A:** Accountable, **C:** Consulted, **I:** Informed.

---

## 5. Estándares de Seguridad y Compliance

Todos los despliegues son auditados automáticamente por **OPA Gatekeeper / Kyverno**.

1.  **Contenedores:** No pueden correr como `root` (MustRunAsNonRoot).
2.  **Límites:** Todos los Pods deben definir `requests` y `limits`.
3.  **Imágenes:** Solo imágenes provenientes de ECR escaneadas (sin vulnerabilidades críticas).

---

## 6. Onboarding y Enlaces Útiles

* [Guía de acceso al clúster (Wiki)](link)
* [Dashboard de Grafana](link)
* [ArgoCD Console](link)
* [Canal de Soporte Slack/Teams](link)
