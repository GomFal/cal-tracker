# Actualización de dependencias con avisos de seguridad

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: backend, lockfile, pruebas
- Prioridad: Alta

## Resumen

Resolver los avisos conocidos de las dependencias de ejecución y demostrar que las versiones resultantes son compatibles con las rutas realmente usadas.

## Problema y motivación

Mantener paquetes con avisos abiertos acumula riesgo y hace más difícil distinguir exposición aplicable de ruido del escáner.

## Contexto actual verificado

La auditoría de Bun informó 14 avisos: 3 altos, 10 medios y 1 bajo. Entre los paquetes directos observados estaban `drizzle-orm 0.44.7` y `hono 4.12.18`; no se demostró que un exploit concreto fuese alcanzable con la configuración actual.

## Objetivos

- Actualizar dependencias directas y transitivas afectadas con cambios mínimos compatibles.
- Documentar cualquier aviso aceptado temporalmente con alcance, compensación y caducidad.
- Evitar regresiones en auth, base de datos, streaming y contratos HTTP.

## Requisitos funcionales

- La resolución final no debe contener avisos altos conocidos aplicables.
- Hono, Drizzle y cualquier dependencia con aviso alto se actualizarán a una versión corregida compatible.
- Los avisos medios y bajos se corregirán en esta entrega solo cuando no exijan cambios relevantes ni amplíen el alcance.
- Cada excepción debe tener propietario, justificación verificable y fecha de revisión.
- Deben ejecutarse tests de backend y escenarios específicos de las APIs afectadas.
- El lockfile debe ser reproducible y revisable.

## Criterios de aceptación

- El escáner aprobado no informa vulnerabilidades altas sin excepción vigente.
- Typecheck, tests y build pasan con el lockfile actualizado.
- Las rutas de Hono y consultas Drizzle usadas por producción conservan su comportamiento.
- El informe distingue versión corregida, no aplicabilidad y riesgo aceptado.

## Impacto previsto en el proyecto

Manifiestos, lockfile, código incompatible solo si es necesario y cobertura backend.

## Decisiones confirmadas

- Los avisos altos son parte del alcance obligatorio del MVP.
- Los avisos medios/bajos se resolverán oportunistamente cuando el cambio sea pequeño y compatible.
- No se creará todavía un SLA formal ni un proceso permanente de aceptación de riesgo.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
