# Firma de confianza para APK de producción

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Android, CI/CD, gestión de secretos
- Prioridad: Crítica

## Resumen

Garantizar que todo APK `prod` publicado se firma exclusivamente con una clave de lanzamiento controlada y que la canalización falla de forma cerrada si esa identidad no está disponible.

## Problema y motivación

Una aplicación publicada con la clave debug no establece una identidad de editor protegida y dificulta una cadena de actualización confiable.

## Contexto actual verificado

`.github/workflows/mobile-apk-deploy.yml` activa `ALLOW_DEBUG_SIGNING=1`; `scripts/mobile/build-android.sh` permite esa excepción y `apps/mobile/android/app/build.gradle.kts` cae a la firma debug si falta la configuración release. El APK de producción inspeccionado en la auditoría estaba firmado por el certificado Android Debug.

## Objetivos

- Separar identidades de firma de desarrollo y producción.
- Impedir por diseño la publicación de un `prod` firmado en debug.
- Permitir rotación, recuperación y verificación de la clave sin exponerla.

## Fuera de alcance

- Migrar la distribución a una tienda concreta.
- Rediseñar el actualizador dentro de la app.

## Requisitos funcionales

- La build `prod` debe requerir material de firma release procedente de un almacén de secretos aprobado.
- La CI debe comprobar el certificado del APK antes de publicarlo.
- La clave, contraseñas y copias de recuperación no deben aparecer en repositorio, artefactos ni logs.
- Las builds locales debug deben seguir siendo posibles sin la clave release.

## Criterios de aceptación

- Una ejecución `prod` sin clave release falla antes de publicar.
- El fingerprint del certificado publicado coincide con el valor aprobado.
- Ninguna ruta de CI de producción establece `ALLOW_DEBUG_SIGNING=1`.
- Existe un procedimiento probado de custodia y recuperación de la clave.

## Impacto previsto en el proyecto

Gradle, script de build, workflow móvil y secretos de GitHub/operaciones.

## Decisiones confirmadas

- Todo APK `prod` se firmará con una clave release real almacenada en secretos protegidos de GitHub.
- Existirá una copia offline cifrada de la clave de firma.
- Se conserva el canal actual de publicación directa de APK durante el MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP; la asignación nominal de custodios es una tarea operativa previa a publicar, no una decisión funcional adicional.
