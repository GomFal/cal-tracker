# Borrado y retención real de chats y transcripciones

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: backend, PostgreSQL, panel admin, móvil, privacidad
- Prioridad: Alta

## Resumen

Definir y aplicar un ciclo de vida verificable para conversaciones, mensajes, transcripciones y derivados, de modo que «eliminar» tenga un efecto comprensible en todas las copias activas.

## Problema y motivación

Ocultar una conversación solo de la vista del usuario no satisface la expectativa normal de borrado ni controla la acumulación de texto nutricional o de salud.

## Contexto actual verificado

El endpoint DELETE oculta conversaciones, y `agentChat.test.ts` confirma que los mensajes permanecen almacenados. El panel admin puede consultar conversaciones ocultas y transcripciones con texto crudo. La caché móvil elimina una conversación local concreta, pero al cerrar sesión solo se desactiva el usuario de chat.

## Objetivos

- Informar claramente qué se conserva, para qué y durante cuánto tiempo.
- Propagar borrado a mensajes, transcripciones, telemetría identificable, cachés y conjuntos derivados.
- Conservar únicamente excepciones legales o antifraude explícitas y minimizadas.

## Experiencia y flujo esperado

El usuario solicita eliminar una conversación, recibe el alcance y estado de la operación, y deja de verla inmediatamente. El backend completa el borrado de todas las copias activas dentro de un plazo publicado y confirma o informa cualquier excepción.

## Requisitos funcionales

- Debe existir una política por categoría: conversación, mensaje, audio temporal, transcripción, traza, backup y dato derivado.
- Chats y mensajes se conservarán mientras exista la cuenta o hasta que el usuario elimine la conversación.
- El contenido de una conversación eliminada desaparecerá del almacenamiento activo en menos de 24 horas.
- El audio temporal se eliminará al finalizar o fallar la transcripción; la telemetría que contenga texto crudo tendrá una retención máxima de 30 días.
- El borrado debe ser idempotente, auditable sin conservar el contenido eliminado y accesible al usuario afectado.
- Panel admin y APIs no deben recuperar contenido borrado salvo retención excepcional autorizada.
- Las copias de seguridad deben expirar el contenido por su ciclo normal y evitar su reintroducción en restauraciones.

## Casos límite y errores

- Borrado durante un stream o trabajo de agente activo.
- Restauración de un backup que contiene datos ya eliminados.
- Contenido ya incluido en un dataset o enviado a un encargado.

## Criterios de aceptación

- Tras el plazo aprobado, una búsqueda operativa por ID no recupera contenido ni transcripción.
- El cliente local elimina el contenido afectado y no lo repuebla por stale-while-revalidate.
- El registro de borrado contiene IDs, tiempos y resultado, no el texto.
- Una restauración aplica un ledger de supresiones antes de reabrir el servicio.

## Impacto previsto en el proyecto

Modelo de datos, repositorios, telemetría admin, caches móviles, backups, privacidad y contratos API.

## Supuestos

- El borrado será asíncrono, con ocultación inmediata y sin papelera de contenido sensible.

## Decisiones confirmadas

- Los chats se conservan hasta que el usuario los elimine o desaparezca su cuenta.
- Mensajes y transcripciones se borran definitivamente del almacenamiento activo en menos de 24 horas tras la solicitud.
- El audio temporal no se conserva después de procesarse.
- El texto crudo de telemetría se elimina como máximo a los 30 días.
- Las copias de seguridad dejan expirar el contenido eliminado dentro de su rotación de 30 días y no deben reintroducirlo al restaurar.

## Preguntas abiertas

- Ninguna para el alcance del MVP; cualquier obligación legal de conservación distinta debe validarse antes del lanzamiento.
