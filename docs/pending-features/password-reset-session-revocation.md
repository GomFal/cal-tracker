# Revocación de sesiones al cambiar la contraseña

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: backend, autenticación, móvil
- Prioridad: Alta

## Resumen

Hacer que un restablecimiento de contraseña exitoso invalide las sesiones existentes y permita al usuario recuperar el control de la cuenta.

## Problema y motivación

Si un atacante ya posee tokens, cambiar la contraseña no lo expulsa y la recuperación de cuenta queda incompleta.

## Contexto actual verificado

`AuthService.confirmPasswordReset` consume el token y actualiza la contraseña. La transacción de `PostgresRepository.consumePasswordReset` no revoca `auth_sessions`; los refresh tokens duran 30 días y los access JWT 15 minutos.

## Objetivos

- Revocar todas las sesiones previas de forma atómica con el cambio de contraseña.
- Comunicar claramente el resultado y permitir iniciar una sesión nueva segura.

## Requisitos funcionales

- Al confirmar el reset deben invalidarse todos los refresh tokens del usuario.
- La revocación y actualización de contraseña deben tener semántica atómica.
- El reset no iniciará una sesión nueva; la persona deberá autenticarse de nuevo.
- Los clientes deben tratar el siguiente rechazo como sesión finalizada, no como fallo transitorio.
- Debe registrarse un evento de auditoría sin almacenar el token ni la contraseña.

## Casos límite y errores

- Dos confirmaciones concurrentes del mismo token.
- Fallo entre actualización de contraseña y revocación.
- Access token ya emitido durante su ventana residual.

## Criterios de aceptación

- Ningún refresh token emitido antes del reset puede rotarse después.
- Un fallo transaccional no deja contraseña nueva con sesiones antiguas activas.
- El usuario puede autenticarse con la nueva contraseña y no con la anterior.
- La auditoría identifica el reset y la revocación global.

## Impacto previsto en el proyecto

Servicio y repositorios de auth, tests backend y tratamiento de sesión expirada en móvil.

## Decisiones confirmadas

- Restablecer la contraseña revocará todos los refresh tokens y exigirá iniciar sesión de nuevo.
- Para reducir complejidad en el MVP, se acepta que un access token emitido antes del cambio siga siendo válido hasta su expiración actual, como máximo 15 minutos.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
