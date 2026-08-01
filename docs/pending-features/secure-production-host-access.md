# Endurecimiento del acceso al VPS de producción

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: VPS, SSH, firewall, operaciones
- Prioridad: Crítica

## Resumen

Reducir la exposición administrativa del servidor de producción eliminando el acceso directo por contraseña a `root` y añadiendo controles de red, bloqueo y auditoría que mantengan una vía de recuperación probada.

## Problema y motivación

Una credencial reutilizada, filtrada o atacada por fuerza bruta podría otorgar control total del host. El impacto alcanza datos, secretos, despliegues y disponibilidad.

## Contexto actual verificado

El 2026-07-16 el host aceptaba SSH público para `root` con contraseña, `fail2ban` no estaba activo y UFW permitía el puerto 22 desde cualquier origen. `AGENTS.md` documenta además el acceso operativo directo como `root`. No se verificó una intrusión.

## Objetivos

- Usar identidades administrativas nominales, claves fuertes y privilegios mínimos.
- Bloquear contraseñas y acceso SSH directo de `root` después de probar una vía alternativa.
- Limitar y observar intentos de acceso sin perder capacidad de recuperación.

## Fuera de alcance

- Investigación forense histórica.
- Sustitución completa del proveedor o del VPS.
- Formalizar y ensayar una custodia avanzada del acceso de emergencia durante la fase de validación.

## Requisitos funcionales

- Debe existir al menos una cuenta nominal con clave y elevación controlada antes de cerrar `root`.
- SSH seguirá expuesto públicamente por el momento y aceptará únicamente autenticación mediante clave.
- El acceso debe aplicar defensa ante fuerza bruta y una política de firewall explícita.
- Deben conservarse registros y alertas útiles sin incluir secretos.
- Antes de cambiar SSH debe verificarse una vía básica de recuperación mediante la consola ya disponible del proveedor; la custodia y ensayo periódico se difieren.

## Casos límite y errores

- Rotación o pérdida de la última clave válida.
- Cambio de IP del personal autorizado.
- Automatizaciones que hoy dependan del usuario `root`.

## Criterios de aceptación

- Un intento SSH por contraseña y un inicio directo como `root` son rechazados.
- Un operador nominal autorizado puede entrar y elevar privilegios.
- Intentos repetidos generan bloqueo o limitación observable.
- El firewall expone solo servicios aprobados y existe acceso básico a la consola del proveedor antes del cambio.

## Impacto previsto en el proyecto

Configuración del host, secretos de CI, documentación operativa y posiblemente el usuario remoto de despliegue.

## Decisiones confirmadas

- El cierre de `root` no debe ejecutarse antes de validar la ruta alternativa.
- No se incorporará Tailscale ni otra VPN en esta fase para mantener sencilla la operación.
- Se deshabilitará completamente la autenticación SSH mediante contraseña.
- Se deshabilitará el login SSH directo de `root`.
- El acceso administrativo normal utilizará un usuario nominal autenticado mediante clave y elevación con `sudo`.
- La definición formal del custodio y la prueba periódica del acceso de emergencia quedan pendientes para después de la validación del MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
