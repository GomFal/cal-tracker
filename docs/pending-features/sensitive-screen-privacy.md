# Protección de capturas, grabaciones y vistas recientes

- Estado: Descartada por decisión de producto
- Última actualización: 2026-07-16
- Superficies afectadas: Android, iOS, Flutter, UX de privacidad
- Prioridad: No aplicable

## Resumen

Se evaluó ocultar contenido sensible en capturas, grabaciones, retransmisiones y la vista de aplicaciones recientes. El producto ha decidido no aplicar estas protecciones.

## Problema y motivación

El sistema operativo y aplicaciones de captura pueden conservar o mostrar datos sensibles cuando la app pasa a segundo plano o se comparte pantalla.

## Contexto actual verificado

No se encontró `FLAG_SECURE`, overlay de privacidad en iOS ni un control equivalente por pantalla. La app muestra conversaciones, datos nutricionales y formularios de autenticación.

## Objetivos

- Conservar una decisión explícita para que este hallazgo no se trate como trabajo pendiente.
- Mantener capturas, grabación, retransmisión y vistas recientes sin restricciones añadidas por BetterCalories.

## Protecciones diferenciadas

Esta feature reúne dos riesgos distintos que pueden configurarse por separado:

1. **Vista de aplicaciones recientes.** Cuando BetterCalories pasa a segundo plano, Android o iOS genera una miniatura para el selector de aplicaciones. Un overlay neutro evita que alguien vea el último chat, peso o resumen nutricional al cambiar entre apps. No impide que el usuario haga una captura mientras está utilizando activamente la app.
2. **Captura, grabación y retransmisión.** En Android, una ventana marcada como segura puede impedir screenshots y ocultarse en pantallas no seguras o screen sharing. En iOS se puede detectar grabación/mirroring y cubrir el contenido, pero la notificación de screenshot llega después de realizarse; no existe una garantía general equivalente para impedir una captura manual.

Aplicar el segundo control a toda la app ofrece más privacidad, pero impide compartir capturas legítimas, complica soporte y puede afectar herramientas de accesibilidad o demostración. Aplicarlo solo a rutas sensibles mantiene esas posibilidades en resúmenes compartibles.

Referencias de plataforma: [Android `FLAG_SECURE`](https://developer.android.com/security/fraud-prevention/activities), [captura activa en iOS](https://developer.apple.com/documentation/uikit/uiscreen/captureddidchangenotification) y [notificación de screenshot en iOS](https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification).

## Requisitos funcionales

- No añadir `FLAG_SECURE` ni controles equivalentes.
- No cubrir el contenido cuando la app pase a segundo plano con el único propósito de ocultar la miniatura del sistema.
- No detectar ni bloquear screenshots, grabación, mirroring, casting o screen sharing.

## Criterios de aceptación

- No se crea trabajo de implementación asociado a este hallazgo.
- La documentación de seguridad no presenta la protección de pantalla como requisito pendiente.

## Impacto previsto en el proyecto

Ninguno: no se modificará Flutter ni la configuración nativa por este hallazgo.

## Decisiones confirmadas

- Las capturas, grabaciones y mecanismos relacionados no se consideran un riesgo que el producto quiera mitigar.
- No se protegerán pantallas ni miniaturas de aplicaciones recientes.

## Preguntas abiertas

- Ninguna.
