# aws-eks-standards
aws EKS standards for Enterprise Cloud Adoption

 *  **Workshop EKS**

## **Intro:  Kubernetes Trirreme-fleet**

<img width="1178" height="770" alt="Screenshot 2025-12-14 at 1 39 04 PM" src="https://github.com/user-attachments/assets/c7484454-1a9b-46b3-b2f2-7371135582ec" />

## **Intro: Most Used Commands for Amazon EKS (Elastic Kubernetes Service)**


These AWS CLI commands are essential for managing the EKS control plane and integrating it with your local kubectl and eksctl tooling.

<img width="638" height="891" alt="Screenshot 2025-12-04 at 10 16 51 PM" src="https://github.com/user-attachments/assets/20bc4170-40ec-4cc7-84c0-b79df65df472" />

## Category	**Action**/	**Command** Example

 * Cluster Management	List all cluster names	
```
aws eks list-clusters
 ```

 *  Get cluster details	
```
aws eks describe-cluster --name <cluster-name>
```

 * Create an EKS cluster	
```
aws eks create-cluster --name <name> --version 1.29 --role-arn <role-arn> --resources-vpc-config ...
```

 * Delete a cluster	
```
aws eks delete-cluster --name <cluster-name>
```

 * Kubeconfig	Crucial: Update local ~/.kube/config file to connect kubectl to the EKS cluster	
```
aws eks update-kubeconfig --name <cluster-name>
```

 * Update with assumed role credentials	
```
aws eks update-kubeconfig --name <cluster-name> --role-arn <management-role-arn>
```

 * Node Groups	List node groups in a cluster	
```
aws eks list-nodegroups --cluster-name <cluster-name>
```

 * Describe a node group	
```
aws eks describe-nodegroup --cluster-name <name> --nodegroup-name <name>
```

 * Create a managed node group	
```
aws eks create-nodegroup --cluster-name <name> --nodegroup-name <name> --node-role <arn> --subnet-ids ...
```

 * Delete a node group	
```
aws eks delete-nodegroup --cluster-name <name> --nodegroup-name <name>
```

 * Add-ons	List installed EKS add-ons	
```
aws eks list-addons --cluster-name <cluster-name>
```

 * Create an EKS add-on	
```
aws eks create-addon --cluster-name <name> --addon-name vpc-cni
```

# Strategic use of Kubernetes add-ons, combined with a hardened cluster baseline, enables an **enterprise-grade**, resilient fleet of clusters designed to securely orchestrate and scale containerized workloads across the organization.

<img width="612" height="500" alt="Screenshot 2025-12-05 at 3 48 15 PM" src="https://github.com/user-attachments/assets/f4dc6c6c-efd9-49b7-aa83-e6c215f0bd01" />


#  AWS EKS Enterprise Standard: 
# [Nombre del Clúster/Proyecto]

| Control de Documento | Detalle |
| :--- | :--- |
| **ID del Documento** | REF-EKS-001 |
| **Versión** | 1.0.0 (Draft) |
| **Clasificación** | Interno  |
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

<img width="1379" height="779" alt="modernize-applications-with-microservices-using-amazon-eks" src="https://github.com/user-attachments/assets/456bd68a-ef65-4a87-8e89-6609c4ccd3a6" />

 * https://docs.aws.amazon.com/architecture-diagrams/latest/modernize-applications-with-microservices-using-amazon-eks/modernize-applications-with-microservices-using-amazon-eks.html?did=wp_card&trk=wp_card

### 2.1 Componentes del Blueprint

<img width="1789" height="800" alt="Screenshot 2025-12-05 at 4 15 13 PM" src="https://github.com/user-attachments/assets/073b48a6-35f3-4d0e-bf80-bcd9fb223401" />


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
* ## Amazon Q
* Amazon Q is a generative AI assistant that can help companies streamline processes, get to decisions faster, and improve employee productivity. It can help every employee gain insights into their data and accelerate their tasks.
<img width="1783" height="959" alt="Screenshot 2025-12-06 at 12 34 06 PM" src="https://github.com/user-attachments/assets/ab61e264-b5e9-4397-8d49-ca3de26db472" />


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
