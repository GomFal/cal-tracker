# Proveniencia y análisis de la cadena de suministro

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: CI/CD, contenedores, Bun, Python, Gradle, releases
- Prioridad: Alta

## Resumen

Evitar variaciones accidentales de build durante el MVP fijando las entradas principales. SBOM, attestations, firma de contenedores y escáneres adicionales se difieren hasta después de validar el producto.

## Problema y motivación

Referencias mutables o dependencias poco fijadas permiten cambios no revisados entre dos builds y dificultan responder a un compromiso de proveedor.

## Contexto actual verificado

La auditoría encontró acciones por tags mayores, Bun `latest`, imágenes base por tags mutables, dependencias Python sin fijación completa y ausencia de escaneo de secretos/imágenes, SBOM o firma de artefactos en los workflows revisados.

## Objetivos

- Fijar Bun e imágenes base a versiones concretas y revisables.
- Mantener instalaciones reproducibles mediante lockfiles congelados.
- Evitar incorporar overhead de gobierno avanzado en el MVP.

## Requisitos funcionales

- Bun debe usar una versión exacta en CI y documentación de build, nunca `latest`.
- Las imágenes base de producción deben usar versiones concretas; su actualización debe pasar por revisión normal.
- Las instalaciones deben conservar `--frozen-lockfile` o el equivalente del ecosistema.
- Los tags mayores existentes de GitHub Actions pueden mantenerse durante el MVP.

## Casos límite y errores

- Aviso sin parche disponible.
- Base image retirada o firma expirada.
- Falso positivo que bloquearía una corrección urgente.

## Criterios de aceptación

- Repetir una build con las mismas entradas resuelve las mismas versiones.
- Ningún workflow de producción solicita Bun `latest` ni una imagen base sin versión concreta.
- Backend y móvil continúan pasando sus builds y tests con las versiones fijadas.

## Impacto previsto en el proyecto

Workflows, Dockerfiles, documentación de toolchain y lockfiles.

## Decisiones confirmadas

- Se fijarán versiones exactas de Bun y versiones concretas de imágenes base.
- Se mantendrán lockfiles congelados.
- SBOM, attestations, firma de contenedores, escáneres nuevos y fijación por commit de todas las Actions quedan diferidos hasta después del MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
