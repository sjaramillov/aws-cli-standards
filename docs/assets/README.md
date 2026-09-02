# Registro de las ilustraciones

Última revisión: **2026-09-02**.

Estas imágenes recuperan la mitología griega y el estilo de pizarra de la documentación histórica sin restaurar sus
errores técnicos. Se generaron con el generador de imágenes integrado de OpenAI, usando como referencia visual los
assets enlazados por el repositorio en el commit `25fc8e3`. Los PNG finales están versionados para no depender de URLs
temporales de `user-attachments`.

| Asset | Propósito | Resolución |
| --- | --- | --- |
| [`eks-olympus-control-plane-fleet.png`](eks-olympus-control-plane-fleet.png) | Separar el control plane administrado por AWS de la flota de worker nodes de un clúster | 1536 × 1024 |
| [`kubernetes-worker-node-trireme.png`](kubernetes-worker-node-trireme.png) | Mostrar kubelet, runtime, Pods, contenedores y almacenamiento dentro de un worker node | 1536 × 1024 |
| [`eks-addons-fleet.png`](eks-addons-fleet.png) | Explicar la distribución y el modelo de gestión de VPC CNI, kube-proxy y CoreDNS | 1536 × 1024 |

## Prompts efectivos

La generación es no determinista: estos prompts registran la intención y las restricciones aplicadas, pero no bastan
para reproducir los mismos píxeles.

### Control plane y flota

> Pizarra educativa horizontal, dibujada a mano sobre pergamino, con mitología griega cálida. Título “EL OLIMPO
> COORDINA; LA FLOTA EJECUTA”. Dentro de una nube rotulada “CONTROL PLANE (AWS)”, situar API SERVER al centro y
> ETCD, SCHEDULER y CONTROLLERS como responsabilidades separadas. ETCD conserva “Kubernetes API state”; scheduler
> asigna un Pod pendiente a un nodo; controllers reconcilian estado deseado y actual. Colocar X-ENI directamente bajo
> el API server, en la frontera de “VPC DEL CLIENTE”, con un canal “API requests · assignments · status” y tres ramas
> hacia tres trirremes; cada trirreme es un WORKER NODE con KUBELET y PODS. No dibujar conexiones directas desde etcd,
> scheduler o controllers a los nodos, ni representar el control plane como un único Zeus.

### Anatomía del worker node

> Pizarra educativa horizontal titulada “ANATOMÍA DE UN WORKER NODE”. Una trirreme completa representa un worker
> node: kubelet como capitán, container runtime como motor y kube-proxy como navegante de reglas locales. Dibujar dos
> límites de Pod; uno contiene un contenedor y `emptyDir`, el otro contiene dos contenedores, para dejar claro que Pod
> no equivale a contenedor. Mostrar un persistent volume en el muelle, fuera del nodo. No usar Docker Engine,
> Dashboard, `hostPath` ni presentar kube-proxy como un proxy central.

### Add-ons

> Pizarra educativa horizontal titulada “LOS AUXILIARES DE LA FLOTA”, limitada a EKS con Managed Node Groups. Mostrar
> el “CONTROL PLANE (AWS)” fuera del “CUSTOMER VPC” y tres worker nodes en el data plane. VPC CNI y kube-proxy aparecen
> como DaemonSets en cada nodo; VPC CNI asigna IPs de Pods y kube-proxy programa reglas locales de Services. CoreDNS
> aparece como dos réplicas de un Deployment y solo resuelve nombres. “EKS add-on” y “self-managed” apuntan a los
> mismos componentes para explicar que cambia su gestión, no su ubicación. No ubicar add-ons en el control plane ni
> generalizar la escena a Auto Mode o Fargate.

## Revisión y límites

- Se inspeccionaron los PNG a resolución original para comprobar texto, conexiones, alcance y ausencia de datos
  sensibles.
- Las tablas y leyendas próximas a cada imagen explican simplificaciones como la X-ENI singular, las réplicas de
  CoreDNS y el camino PVC/PV/CSI.
- Mermaid, el texto y las fuentes primarias son la referencia técnica. CI verifica existencia y enlaces de los assets,
  pero no puede validar semánticamente sus píxeles.
- Los assets se distribuyen bajo la [licencia MIT del repositorio](../../LICENSE).
