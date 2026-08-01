# Respuestas de autenticación resistentes a enumeración

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: backend, móvil, correo, soporte
- Prioridad: Media

## Resumen

Evitar que registro, acceso y recuperación permitan confirmar de forma automatizada qué correos tienen cuenta, conservando una experiencia útil para la persona legítima.

## Problema y motivación

La enumeración facilita phishing dirigido, credential stuffing y descubrimiento de uso de un servicio relacionado con nutrición o salud.

## Contexto actual verificado

El registro devuelve el código explícito `email_already_registered`. La recuperación de contraseña ya responde de forma neutra cuando el usuario no existe, y `develop` incorpora confirmación de correo para registros por contraseña.

## Objetivos

- Unificar respuestas públicas indistinguibles por estado de cuenta.
- Informar de forma segura al propietario mediante correo y flujos autenticados.
- Reducir diferencias de contenido y tiempo medibles.

## Requisitos funcionales

- Registro y recuperación deben responder con un mensaje neutral y un contrato común.
- Si la cuenta existe, el correo puede orientar a login/recuperación sin revelar el estado al solicitante web.
- El procesamiento debe limitar diferencias de tiempo observables y estar sujeto a límites de abuso.
- Logs internos pueden conservar la causa con acceso restringido.

## Criterios de aceptación

- Correos existentes, pendientes e inexistentes producen status, esquema y mensaje equivalentes.
- Tests estadísticos básicos no detectan una diferencia temporal trivialmente explotable.
- El propietario recibe una vía útil sin que el solicitante obtenga confirmación.
- Rate limiting evita usar el correo como oráculo o canal de spam.

## Impacto previsto en el proyecto

Contratos auth, servicio de correo, traducciones y tests backend/móvil.

## Decisiones confirmadas

- Registro y recuperación responderán de forma neutra para cuentas existentes, pendientes e inexistentes.
- Solo se enviará el correo funcional necesario para la operación válida.
- No se enviará una notificación adicional a una cuenta existente por cada intento de registro duplicado.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
