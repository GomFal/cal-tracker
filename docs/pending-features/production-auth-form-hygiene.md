# Formulario de acceso sin credenciales demo

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: móvil, autenticación, flavors, tests
- Prioridad: Media

## Resumen

Mostrar campos de autenticación vacíos en builds dev/prod distribuidas y reservar datos de demostración para fixtures locales explícitos.

## Problema y motivación

Credenciales precargadas animan a probar secretos conocidos, pueden confundirse con una cuenta real y reducen la confianza en la pantalla de acceso.

## Contexto actual verificado

`apps/mobile/lib/ui/features/auth/views/auth_screen.dart` inicializa email, contraseña y nombre con `demo@example.com`, `password123` y `Test User` sin condicionarlo al flavor.

## Objetivos

- Entregar formularios vacíos en dev/prod.
- Conservar demos reproducibles solo dentro del toolkit/local fake sin tocar backend real.
- Evitar que tests dependan de valores productivos implícitos.

## Requisitos funcionales

- Campos de acceso y registro deben iniciar vacíos en toda build conectada a un backend.
- El toolkit local puede conservar usuarios ficticios mediante repositorios fake, sin precargar credenciales visibles ni llamar al backend.
- Contraseñas de ejemplo no deben aparecer en artefactos release ni telemetría.

## Criterios de aceptación

- Instalar un APK dev/prod limpio muestra los tres campos vacíos.
- Los tests introducen sus propias credenciales mediante fixtures.
- El flujo local de demostración no realiza llamadas de auth al backend.

## Impacto previsto en el proyecto

Pantalla auth, bootstrap/flavors locales, tests widget e integración.

## Decisiones confirmadas

- Dev y producción mostrarán todos los campos de autenticación vacíos.
- El toolkit local podrá conservar fixtures internos únicamente mediante repositorios fake.
- No se añadirá un botón ni credenciales visibles de «Entrar como demo».

## Preguntas abiertas

- Ninguna para el alcance del MVP.
