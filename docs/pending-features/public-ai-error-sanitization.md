# Saneamiento de errores públicos de IA y STT

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: API, SSE, STT, proveedores LLM, observabilidad, móvil
- Prioridad: Alta

## Resumen

Separar el mensaje seguro que recibe el cliente del detalle técnico que necesitan logs y trazas, especialmente en respuestas en streaming.

## Problema y motivación

Mensajes crudos de proveedores pueden revelar endpoints, modelos, payloads, configuración o texto no apto para usuarios, además de crear contratos inestables.

## Contexto actual verificado

Las rutas de streaming y STT en `apps/backend/src/http/app.ts` y `speechToTextProvider.ts` propagan en algunos casos `Error.message` o texto del proveedor. El middleware HTTP general sí devuelve mensajes más genéricos, por lo que el comportamiento no es uniforme.

## Objetivos

- Ofrecer códigos y mensajes públicos estables, localizables y no sensibles.
- Conservar el diagnóstico completo solo en observabilidad protegida y correlacionada.
- Tratar de forma consistente errores antes y después de abrir SSE.

## Requisitos funcionales

- Todo fallo público debe mapearse a un catálogo de códigos seguros con `traceId`.
- El catálogo inicial se limitará a validación, autenticación, límite alcanzado, proveedor temporalmente no disponible y error interno.
- El detalle del proveedor no debe aparecer en JSON, SSE ni telemetría de cliente.
- Logs internos deben redactar secretos y datos personales antes de persistir.
- El móvil debe distinguir reintento, autenticación, validación y fallo temporal sin analizar texto libre.

## Criterios de aceptación

- Errores simulados con claves, URLs o payloads no filtran esos valores al cliente.
- JSON y SSE usan el mismo código semántico para el mismo fallo.
- El operador encuentra el detalle mediante `traceId` con acceso autorizado.
- Tests cubren fallos de STT, LLM, tool call y conexión interrumpida.

## Impacto previsto en el proyecto

Adaptadores de proveedor, manejadores HTTP/SSE, contratos, localización móvil y telemetría.

## Decisiones confirmadas

- El cliente solo recibirá una categoría estable, un mensaje seguro y el `traceId`.
- El detalle técnico se conservará únicamente en los logs actuales, aplicando redacción de secretos y datos personales.
- El MVP no incorporará un sistema adicional de observabilidad ni una política nueva de retención de logs para esta feature.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
