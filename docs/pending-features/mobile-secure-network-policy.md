# Política de red segura en móvil

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Android, Flutter, configuración por entorno
- Prioridad: Media

## Resumen

Bloquear tráfico HTTP en builds distribuibles y conservar una excepción local explícita y limitada para desarrollo contra el emulador.

## Problema y motivación

Permitir cleartext globalmente hace posible que una configuración errónea envíe tokens y datos sensibles sin TLS.

## Contexto actual verificado

El manifest principal declara `android:usesCleartextTraffic="true"`. `ApiConfig.fromEnvironment` usa `http://localhost:3000` como valor por defecto, aunque las instrucciones oficiales de dev desplegado y producción usan HTTPS y el emulador local usa `10.0.2.2`.

## Objetivos

- Hacer imposible cleartext en `prod` y en builds dev distribuidas.
- Mantener desarrollo local mediante una configuración de red acotada al flavor local/debug.
- Fallar temprano si una build release carece de URL HTTPS válida.

## Requisitos funcionales

- `prod` debe rechazar cualquier API base que no sea HTTPS.
- El flavor `dev` distribuido también debe exigir HTTPS.
- La excepción HTTP debe existir solo en variantes locales aprobadas y para hosts específicos.
- Ninguna build release debe depender del default localhost.
- Errores de configuración deben ser observables sin imprimir tokens.

## Criterios de aceptación

- Una build `prod` no puede conectar a un endpoint HTTP de prueba.
- El flavor local sigue conectando a `http://10.0.2.2:3000` en el emulador.
- La CI bloquea release con API base ausente, HTTP o de host no aprobado.
- Tests de manifest/configuración cubren cada flavor.

## Impacto previsto en el proyecto

Manifests por variante, network security config, `ApiConfig`, scripts de build y tests Android/Flutter.

## Decisiones confirmadas

- Producción y dev distribuido utilizarán exclusivamente HTTPS.
- HTTP se permitirá solo al flavor local/debug para `10.0.2.2` y los hosts locales explícitamente necesarios.
- No se implementará certificate pinning durante el MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
