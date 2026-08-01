# Cadena de despliegue de producción verificable

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: GitHub Actions, SSH, VPS, gobierno de releases
- Prioridad: Crítica

## Resumen

Exigir identidad del host verificada, aprobación y procedencia comprobable para que solo releases autorizadas puedan desplegar producción.

## Problema y motivación

La confianza en una clave capturada en el momento y un tag amplio permiten que una manipulación de red, credenciales o flujo Git tenga impacto directo en producción.

## Contexto actual verificado

Los workflows usan `ssh-keyscan` durante la ejecución, despliegan tags `v*` y delegan el acceso al usuario configurado en secretos, actualmente alineado con acceso operativo privilegiado. No se observó en el repositorio una verificación de fingerprint fijado ni reglas de aprobación demostrables.

## Objetivos

- Verificar de antemano la identidad del host remoto.
- Mantener el mecanismo actual de promoción a producción mediante tags `v*`.
- Vincular artefacto, revisión, aprobación y despliegue mediante evidencia auditable.

## Requisitos funcionales

- La clave SSH del host debe compararse con fingerprints administrados y rotables, no aprenderse por TOFU en cada job.
- Producción debe continuar desplegándose automáticamente con la metodología actual cuando se publica un tag `v*`; no se añadirá una aprobación manual ni se exigirá firma del tag en esta fase.
- El usuario de despliegue debe tener permisos limitados a su función.
- Debe poder identificarse exactamente qué commit y artefacto están desplegados y quién lo aprobó.

## Criterios de aceptación

- Una clave de host inesperada bloquea el job.
- Crear un tag sin cumplir la política no despliega producción.
- El despliegue no necesita una sesión SSH general como `root`.
- Existe trazabilidad inmutable desde commit hasta artefacto y entorno.

## Impacto previsto en el proyecto

Workflows backend/móvil, entornos protegidos de GitHub, secretos, usuarios del VPS y runbooks de release.

## Decisiones confirmadas

- Se conserva la metodología actual de despliegue a producción mediante tags `v*`.
- No se incorporarán tags firmados, una nueva rama de promoción ni aprobación manual obligatoria en esta fase.
- El cambio de usuario remoto necesario para eliminar el login de `root` debe conservar el mismo flujo automático de despliegue.
- La identidad SSH del servidor se validará mediante un fingerprint fijado; no se confiará en el resultado de `ssh-keyscan` obtenido durante cada job.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
