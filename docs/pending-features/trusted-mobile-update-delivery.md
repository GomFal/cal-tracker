# Entrega confiable de actualizaciones móviles

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Flutter, publicación de APK, manifest de actualización, navegador/Android
- Prioridad: Media

## Resumen

Garantizar que el manifest y el APK ofrecidos por el actualizador pertenecen al canal y editor esperados, usando HTTPS, allowlist e integridad verificable.

## Problema y motivación

Mostrar una descarga desde un esquema u origen arbitrario expone a phishing o artefactos manipulados, aunque Android impida instalar encima una app firmada por otra clave.

## Contexto actual verificado

`MobileUpdateManifest` parsea `sha256`, pero `MobileUpdateService` no lo valida. `openDownload` acepta cualquier URI con esquema y el manifest se deriva del API base. El servidor publica un `.sha256`, pero la app solo abre la URL externamente.

## Objetivos

- Aceptar manifests y APK únicamente desde orígenes HTTPS aprobados.
- Apoyarse durante la distribución directa en TLS, allowlist y la identidad de firma release de Android.
- Alinear canal, package ID, versión y certificado de firma.
- Retirar el actualizador propio cuando Play Store pase a gestionar las actualizaciones.

## Requisitos funcionales

- Manifest y APK deben usar HTTPS y hosts allowlisted por flavor.
- La descarga seguirá delegándose al navegador; no se añadirá descarga/verificación interna ni firma independiente del manifest durante el MVP.
- Version code debe avanzar según política y el package/canal deben coincidir.
- Un fallo de verificación debe bloquear la acción y mostrar un mensaje seguro.

## Casos límite y errores

- CDN redirige a otro host.
- Manifest válido apunta a versión inferior o a otro flavor.
- Descarga parcial o hash correcto de un artefacto firmado por identidad no aprobada.

## Criterios de aceptación

- Esquemas no HTTPS, hosts no permitidos, downgrade y canales cruzados son rechazados.
- Una actualización válida de cada flavor se abre o instala por el flujo esperado.
- Tests cubren redirects, JSON manipulado, versión y canales cruzados.
- La identidad del APK coincide con la ficha de firma release.

## Impacto previsto en el proyecto

Servicio/modelos de actualización, publicación de manifests, firma de artefactos y tests.

## Decisiones confirmadas

- El navegador continuará realizando la descarga desde hosts HTTPS oficiales del flavor.
- No se implementará descarga interna, firma adicional del manifest ni comprobación del checksum dentro de la app durante el MVP.
- La confianza se apoya en TLS, allowlist, package/canal correcto y la clave release de Android.
- Este mecanismo es temporal y se eliminará cuando las actualizaciones se distribuyan mediante Play Store.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
