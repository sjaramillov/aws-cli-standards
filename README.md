# aws-cli-standards
aws cli standards for enterprise cloud adoption
# Enterprise Cloud Adoption Standard (AWS)

Este documento define las **instrucciones empresariales estándar para la adopción de nube**, basadas en buenas prácticas de gobierno, seguridad, automatización e integración operacional utilizando AWS CLI y servicios relacionados.

---

## 1. Configuración y Autenticación Empresarial

Todo uso del AWS CLI dentro de la empresa **debe** seguir autenticación basada en roles y configuraciones seguras.

### Estándares Obligatorios

* **Autenticación sin llaves permanentes**: Solo IAM Roles, AWS SSO o STS AssumeRole.
* **Prohibido** usa claves estáticas o credenciales root.
* **Perfiles obligatorios**: Cada equipo debe operar con perfiles definidos en `~/.aws/config`.
* **Región y formato estándar**: Obligatorio establecer región por defecto y formato `json`.
* **Uso de `jq`** para procesamiento estándar de JSON en automatización.

### Ejemplo de configuración empresarial

```bash
# Incorrecto — nunca usar claves embebidas
aws configure

# Correcto — usar un perfil vinculado a SSO o STS
aws configure --profile OpsAdmin
```

---

## 2. Estandarización de Comandos y Scripting

Los comandos deben ser predecibles, repetibles y orientados a automatización.

### 2.1 Salida orientada a máquina

Evita usar tab/tablas en scripts. Usar únicamente `json` o `text`.

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --output json > instances.json
```

### 2.2 Uso obligatorio de JMESPath

Nunca procesar JSON manualmente.

```bash
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,IP:PublicIpAddress}' \
  --output table
```

---

## 3. Gobernanza y Seguridad

### 3.1 Principio de Mínimos Privilegios (PoLP)

Roles y usuarios deben tener solo los permisos estrictamente necesarios.

### 3.2 CloudTrail obligatorio

CloudTrail debe estar activo en todas las cuentas para auditoría de comandos CLI.

### 3.3 Etiquetado estándar de recursos

Cualquier script que cree recursos **debe** incluir etiquetas corporativas asociadas a centro de costos y proyecto.

```bash
aws ec2 run-instances --image-id ami-0abcdef1234567890 \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=Finance},{Key=Owner,Value=OpsTeam}]'
```

---

## 4. Excelencia Operacional y Automatización

### 4.1 Integración con IaC

El CLI se usa para operaciones y consultas, no para provisionamiento repetible.(automatización en Pipelines - DevOps)

Uso recomendado del CLI:

* Lectura de estado (`describe-*`).
* Operaciones de dataplane (ej. detener instancias).
* Bootstrapping de entornos de Terraform o CloudFormation.

---

## 5. Comandos Empresariales para Operación de Amazon EKS

### 5.1 Gestión de Clusters

* Listar clusters:

```bash
aws eks list-clusters
```

* Describir un cluster:

```bash
aws eks describe-cluster --name <cluster-name>
```

### 5.2 Conexión Kubernetes (kubeconfig)

```bash
aws eks update-kubeconfig --name <cluster-name>
```

Con rol asumido:

```bash
aws eks update-kubeconfig --name <cluster-name> --role-arn <role-arn>
```

### 5.3 Node Groups

```bash
aws eks list-nodegroups --cluster-name <cluster-name>
aws eks create-nodegroup --cluster-name <name> --nodegroup-name <name> --node-role <arn> --subnet-ids ...
```

### 5.4 Add-ons

```bash
aws eks list-addons --cluster-name <cluster-name>
aws eks create-addon --cluster-name <name> --addon-name vpc-cni
```

---

## 6. Requisitos Organizacionales para la Adopción de Nube

### 6.1 Lineamientos de Gobierno

* Uso de **Landing Zones** estándar.
* Políticas SCP para restringir acciones no autorizadas.
* Separación de ambientes: **Prod / Non-Prod / Sandbox**.

### 6.2 Seguridad

* MFA obligatorio.
* Rotación automática de credenciales efímeras.
* Encripción en tránsito y reposo para todos los servicios.

### 6.3 Operaciones

* Uso de CloudWatch para observabilidad.
* Automatización de despliegues con CI/CD.
* Gestión centralizada de logs.

### 6.4 Costos y FinOps

* Cost Allocation Tags obligatorias.
* Alarmas de presupuesto.
* Revisión mensual de gasto por unidad de negocio.

---

## 7. Recursos Adicionales

* AWS CLI Documentation
* AWS Well-Architected Framework
* AWS EKS Best Practices Guide

---

**Documento para adopción corporativa de nube.**
