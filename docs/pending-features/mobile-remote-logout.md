# Cierre de sesión remoto desde móvil

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Flutter, API de auth, almacenamiento local
- Prioridad: Media

## Resumen

Hacer que cerrar sesión desde la app revoque el refresh token en el backend y limpie el estado local incluso cuando la red falla.

## Problema y motivación

Eliminar solo la copia local deja utilizable una credencial robada o copiada y no comunica al servidor la intención de terminar la sesión.

## Contexto actual verificado

`AuthRepository.logout` borra `TokenStorage` y cierra Google, pero no llama al endpoint backend de logout. El backend ya dispone de revocación por refresh token.

## Experiencia y flujo esperado

Al pulsar cerrar sesión, la app deja inmediatamente de mostrar datos del usuario. Intenta revocar la sesión remota; si no hay red, no reabre la sesión local y completa la revocación cuando sea viable o deja que la rotación/expiración limite el token.

## Requisitos funcionales

- La petición de logout debe usar el refresh token antes de destruir su única copia local.
- La limpieza local y navegación no deben quedar bloqueadas por la red.
- Si el backend no está disponible, el MVP hará un intento de revocación con timeout corto, limpiará siempre el dispositivo y no conservará el refresh token para reintentos posteriores.
- Repetir logout debe ser seguro e idempotente.
- No deben registrarse tokens en colas, logs o errores.
- Debe definirse un mecanismo seguro para fallo offline que no reintroduzca la sesión.

## Criterios de aceptación

- Con red, el refresh token deja de funcionar después del logout móvil.
- Sin red, la UI y datos locales se limpian conforme a política y la app no restaura la sesión.
- Reintentos o doble toque no generan errores visibles ni estados parciales.
- Google sign-out y logout backend fallan de manera independiente sin impedir la limpieza local.

## Impacto previsto en el proyecto

API generada/contrato, repositorio y ViewModel de auth, almacenamiento seguro y tests offline.

## Decisiones confirmadas

- Logout móvil intentará revocar la sesión actual en el backend antes de destruir la copia local del refresh token.
- La limpieza local siempre se completará aunque falle la red.
- No se añadirá una cola persistente de revocaciones para el MVP.
- La interfaz específica para cerrar todos los dispositivos queda fuera de esta ficha.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
