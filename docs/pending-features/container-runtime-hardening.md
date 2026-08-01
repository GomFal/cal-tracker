# Endurecimiento de contenedores

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Docker Compose, backend, PostgreSQL, VPS
- Prioridad: Alta

## Resumen

Reducir privilegios y capacidad de movimiento lateral de los contenedores aplicando filesystem, capacidades, seguridad del proceso y recursos mínimos compatibles.

## Problema y motivación

Una vulnerabilidad de aplicación tiene mayor impacto si el proceso puede escribir ampliamente, conservar capacidades Linux innecesarias o agotar el host.

## Contexto actual verificado

Los Compose revisados no declaran `read_only`, `cap_drop`, `no-new-privileges` ni límites de CPU/memoria. Como controles positivos, el backend usa el usuario `bun`, no hay contenedores privilegiados, los puertos del backend se enlazan a loopback y PostgreSQL permanece interno.

## Objetivos

- Ejecutar cada servicio con privilegios y escritura mínimos.
- Contener consumo anómalo sin degradar cargas normales.
- Mantener migraciones, healthchecks, logs y backups operativos.

## Requisitos funcionales

- El contenedor backend debe usar `no-new-privileges` y eliminar capacidades Linux innecesarias.
- El backend debe tener límites básicos de CPU/memoria compatibles con la capacidad actual del VPS y sus smoke tests.
- Secretos y sockets del host no deben montarse sin necesidad.

## Criterios de aceptación

- El backend inicia y pasa smoke tests bajo la política endurecida.
- Un intento de elevar privilegios dentro del backend falla.
- Un test de consumo supera el límite sin derribar servicios no relacionados.
- Backup, restauración y migraciones siguen funcionando por rutas autorizadas.

## Impacto previsto en el proyecto

Compose local y de despliegue, Dockerfile, logging, volúmenes y runbooks.

## Fuera de alcance

- Filesystem de solo lectura durante el MVP.
- Endurecimiento adicional del contenedor PostgreSQL durante el MVP.

## Decisiones confirmadas

- El MVP aplicará `no-new-privileges`, reducción de capacidades y límites básicos únicamente al backend.
- Filesystem de solo lectura y cambios adicionales en PostgreSQL quedan diferidos.

## Preguntas abiertas

- Ninguna para el alcance del MVP; los valores concretos de recursos se calibrarán durante la implementación contra el VPS actual.
