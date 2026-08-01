# Invalidación inmediata de sesiones globales

- Estado: Diferida hasta después del MVP
- Última actualización: 2026-07-16
- Superficies afectadas: backend, autenticación, móvil
- Prioridad: Media

## Resumen

Se evaluó hacer que «cerrar todas las sesiones» invalide también access tokens ya emitidos. Para el MVP se conservarán los JWT actuales y se acepta una ventana residual máxima de 15 minutos.

## Problema y motivación

Una acción de seguridad global crea una expectativa de efecto inmediato que actualmente no se cumple para JWT de acceso aún vigentes.

## Contexto actual verificado

`logoutAll` revoca las filas de refresh session. `verifyAccessToken` valida firma y expiración del JWT, pero no consulta una época de revocación; los access tokens duran 15 minutos.

## Objetivos

- Conservar documentado el riesgo residual aceptado durante la validación.
- Reconsiderar invalidación inmediata si aumenta el riesgo, la duración del token o la escala.

## Requisitos funcionales

- Cada token debe poder compararse con un estado de revocación del usuario o sesión.
- Logout global, reset de contraseña y desactivación de cuenta deben avanzar ese estado según política.
- Fallos del mecanismo no deben aceptar silenciosamente un token revocado.
- Deben existir métricas de rechazos por revocación diferenciadas de expiración.

## Criterios de aceptación

- `logout-all` y reset de contraseña revocan todos los refresh tokens.
- Los access tokens previos expiran de forma natural en un máximo de 15 minutos y no pueden renovarse.
- No se incorpora una consulta de revocación por petición en el MVP.

## Impacto previsto en el proyecto

Ninguno durante el MVP; una fase posterior afectaría claims JWT, middleware auth, almacenamiento y cliente móvil.

## Decisiones confirmadas

- Se acepta explícitamente la validez residual de access tokens durante un máximo de 15 minutos.
- La invalidación inmediata se difiere para evitar estado y comprobaciones adicionales en cada petición del MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
