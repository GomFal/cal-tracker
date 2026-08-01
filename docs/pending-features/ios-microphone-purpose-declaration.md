# Declaración de uso del micrófono en iOS

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: iOS, Flutter, privacidad, localización
- Prioridad: Compatibilidad y privacidad

## Resumen

Declarar de forma precisa por qué BetterCalories solicita micrófono antes de habilitar el flujo de grabación y transcripción en iOS.

## Problema y motivación

iOS requiere una descripción de uso para solicitar permiso; su ausencia puede cerrar la app o impedir la función y deja al usuario sin contexto suficiente.

## Contexto actual verificado

La app usa el paquete `record` mediante `AudioRecorderService`. `ios/Runner/Info.plist` contiene la descripción de cámara, pero no `NSMicrophoneUsageDescription`.

## Objetivos

- Mostrar un propósito claro, específico y coherente con el flujo visible.
- Mantener paridad de intención entre permiso nativo, copy dentro de la app y política de privacidad.
- No solicitar micrófono hasta que la persona inicie una acción que lo necesite.

## Requisitos funcionales

- `Info.plist` debe incluir una descripción precisa del uso para registrar comida por voz/transcribir audio.
- El copy debe estar revisado en inglés y español donde el sistema de build lo permita.
- Denegar, restringir o revocar permiso debe producir un estado recuperable sin bloquear el uso manual.
- Audio temporal y transcripción deben seguir la política de ciclo de vida aprobada.

## Criterios de aceptación

- En una instalación limpia de iOS, tocar grabar muestra el diálogo con el propósito aprobado y no cierra la app.
- Denegar permiso mantiene disponible el registro manual y explica cómo recuperarlo.
- El permiso no se solicita al arrancar ni antes de una intención explícita.
- Tests o validación en dispositivo cubren permitido, denegado y restringido.

## Impacto previsto en el proyecto

`Info.plist`/localizaciones iOS, UX de voz, política de privacidad y pruebas nativas.

## Decisiones confirmadas

- Texto ES: «BetterCalories usa el micrófono cuando eliges registrar una comida por voz, para transcribir el audio y completar tu registro nutricional».
- Texto EN: «BetterCalories uses the microphone when you choose to log a meal by voice, to transcribe the audio and complete your nutrition log».
- Si se deniega el permiso, el registro manual continuará disponible.
- La política de privacidad explicará el envío al proveedor de transcripción cuando corresponda; no se añadirá esa explicación extensa al diálogo nativo.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
