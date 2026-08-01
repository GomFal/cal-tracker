# Caché móvil privada y aislada por usuario

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Flutter, Android/iOS, almacenamiento local, sesión
- Prioridad: Media

## Resumen

Proteger datos nutricionales y conversaciones persistidas en el dispositivo mediante aislamiento, cifrado apropiado, política de backup y limpieza coherente con el cierre de sesión.

## Problema y motivación

Datos de dieta, chats y transcripciones pueden quedar accesibles en preferencias, copias del dispositivo o tras cambiar de cuenta.

## Contexto actual verificado

`NutritionCacheStore`, `AgentChatCacheStore` y `AgentChatSessionStore` serializan JSON mediante `AppPreferencesStorage`. Android no declara una política explícita `allowBackup`/reglas de backup. Al cerrar sesión se borra la caché nutricional activa, pero las tiendas de chat se desactivan sin limpiar sus datos del usuario.

## Objetivos

- Evitar lectura casual o extracción por backup de contenido sensible.
- Garantizar aislamiento estricto entre usuarios del mismo dispositivo.
- Eliminar los datos offline del usuario al cerrar sesión, con comportamiento visible consistente.

## Requisitos funcionales

- Tokens deben permanecer en almacenamiento seguro y nunca mezclarse con caches.
- Para el MVP, el contenido cacheado se apoyará en el sandbox y cifrado general del dispositivo; no se añadirá cifrado de aplicación independiente.
- Backup/restore del sistema debe excluir secretos y datos que no deban migrar.
- La activación de usuario no debe leer claves de otro usuario, aunque falle un logout previo.
- Cerrar sesión debe eliminar la caché nutricional, conversaciones, detalles de chat y la referencia a la sesión activa del usuario.
- Limpieza, expiración y migración de formato deben ser idempotentes.

## Casos límite y errores

- Cambio rápido de cuenta sin red.
- Restauración del backup en otro dispositivo sin claves.
- Cifrado o migración corruptos con datos cacheados todavía visibles.

## Criterios de aceptación

- Una cuenta B no puede recuperar datos locales de A.
- Una extracción de preferencias/backup no contiene texto sensible en claro según el modelo de amenaza aprobado.
- Logout elimina todos los datos cacheados del usuario y la UI no los repuebla ni permite recuperarlos al iniciar otra cuenta.
- Tests cubren aislamiento, expiración, corrupción, migración y limpieza.

## Impacto previsto en el proyecto

Capa de almacenamiento, caches/repositorios, bootstrap de sesión, configuración nativa y tests.

## Decisiones confirmadas

- Por seguridad, cerrar sesión borra chats, sesión de chat, datos nutricionales y demás contenido sensible cacheado de esa cuenta.
- La caché es una optimización local, no un archivo personal que deba sobrevivir al logout.
- La caché se excluirá de los backups del sistema operativo.
- Los tokens seguirán almacenándose mediante el almacenamiento seguro nativo.
- No se intentará proteger la caché frente a un dispositivo rooteado o jailbroken durante el MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
