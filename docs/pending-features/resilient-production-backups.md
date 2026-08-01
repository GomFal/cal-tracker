# Copias de seguridad automatizadas, cifradas y restaurables

- Estado: En exploración
- Última actualización: 2026-07-16
- Superficies afectadas: PostgreSQL, VPS, almacenamiento externo, operaciones
- Prioridad: Crítica

## Resumen

Convertir las copias de PostgreSQL en un servicio automático con cifrado, copia fuera del host, retención definida, monitorización y restauraciones verificadas.

## Problema y motivación

Una copia manual que permanece en el mismo servidor no protege adecuadamente frente a pérdida del host, ransomware, error humano o corrupción silenciosa.

## Contexto actual verificado

`infra/deploy/backup-postgres-schema.sh` genera dumps locales por esquema. En la revisión del VPS había cuatro dumps, el último de 2026-06-02, sin automatización, cifrado externo ni evidencia de pruebas de restauración.

## Objetivos

- Cumplir objetivos explícitos de pérdida máxima de datos y tiempo de recuperación.
- Mantener copias cifradas fuera del dominio de fallo del VPS.
- Detectar fallos y demostrar periódicamente que una copia restaura.

## Requisitos funcionales

- Producción debe generar automáticamente una copia completa al día; no se programarán múltiples copias diarias en esta fase.
- Desarrollo puede aplicar una retención menor y no condicionará la protección de producción.
- Deben cifrarse antes de salir del host y almacenarse con acceso mínimo e inmutable cuando sea viable.
- Deben conservarse las 30 copias diarias más recientes y alertar por antigüedad, integridad o fallo.
- Una restauración manual trimestral, realizada en un entorno aislado, debe validar esquema y datos representativos sin afectar producción.

## Casos límite y errores

- Dump parcial por falta de disco o caída de PostgreSQL.
- Clave de cifrado perdida o rotada.
- Copia correcta pero datos lógicamente corruptos.

## Criterios de aceptación

- Un panel o alerta muestra la edad de la última copia válida.
- La pérdida del VPS no elimina todas las copias.
- Una restauración ensayada cumple los RPO/RTO aprobados.
- El acceso y borrado de copias queda auditado.

## Impacto previsto en el proyecto

Scripts de infraestructura, programación del host, almacenamiento externo, secretos y runbooks.

## Decisiones confirmadas

- Se realizará como máximo una copia programada al día en producción.
- No se adopta un objetivo de pérdida máxima de una hora; con una copia diaria se acepta perder hasta aproximadamente 24 horas de cambios en el peor caso.
- Se conservarán 30 copias totales, correspondientes a los últimos 30 días.
- Las copias estarán cifradas y almacenadas fuera del VPS.
- Los fallos o una copia demasiado antigua generarán una alerta.
- Se ensayará manualmente una restauración cada tres meses.
- La selección de proveedor/región y el tiempo máximo de restauración quedan deliberadamente pendientes durante la fase actual de validación.

## Preguntas abiertas

- Antes de implementar el almacenamiento externo: proveedor/región y tiempo máximo de restauración aceptable.
