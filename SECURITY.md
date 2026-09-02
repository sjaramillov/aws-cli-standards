# Política de seguridad

## Alcance

Este repositorio contiene documentación, scripts de validación local y ejemplos. Son relevantes, entre otros:

- comandos que exponen credenciales o amplían acceso;
- procedimientos que pueden borrar el recurso equivocado;
- ejemplos que crean endpoints, roles o workloads inseguros;
- dependencias/workflows comprometidos;
- secretos publicados por accidente.

## Reportar de forma segura

No abras un issue público con credenciales, tokens, kubeconfigs, account IDs, endpoints privados, datos internos o una
secuencia de explotación. Usa *Private vulnerability reporting* en la pestaña **Security** del repositorio si está
habilitado. Si no lo está, contacta al propietario por un canal privado indicado en su perfil sin incluir el secreto en
el primer mensaje.

Para una inexactitud no sensible, abre un issue con archivo/sección, impacto, fuente primaria y fecha de verificación.

## Si se expuso una credencial

1. Revócala o desactívala inmediatamente en el sistema emisor.
2. Conserva metadatos de auditoría sin volver a copiar el valor.
3. Revisa CloudTrail y uso asociado según el runbook de incidentes.
4. Reporta el incidente de forma privada.
5. Elimina el secreto del contenido y, cuando proceda, del historial; rotar sigue siendo obligatorio.

No esperes una corrección del repositorio para revocar una credencial activa.

## Respuesta

El propietario aún debe publicar un SLA y un contacto privado dedicado. Hasta entonces, evita compartir detalles
sensibles por canales públicos. Consulta la sección de decisiones pendientes en la
[auditoría](docs/auditoria-2026-09.md#decisiones-pendientes-del-propietario).
