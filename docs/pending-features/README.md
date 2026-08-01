# Remediaciones pendientes de seguridad y privacidad

Inventario funcional derivado de la verificación de seguridad revalidada contra `develop` el 2026-07-16. Cada ficha representa una capacidad independiente y conserva por separado hechos verificados, resultado esperado y decisiones aún abiertas.

Ninguna ficha autoriza por sí sola cambios en producción. Las observaciones del VPS son una fotografía puntual de configuración, no un análisis forense ni evidencia de intrusión.

## Criterio de alcance del MVP

- Priorizar únicamente controles necesarios para proteger credenciales, datos de usuarios, integridad del APK, privacidad legal básica y gasto de proveedores.
- Elegir la solución configurable más sencilla que reduzca materialmente el riesgo actual.
- Diferir automatización avanzada, alta madurez operativa y defensa en profundidad cuando no sean necesarias para validar el producto.
- Conservar los aplazamientos de forma explícita para revisarlos antes de escalar el servicio.

## Estado de la exploración

- 18 fichas listas para planificación del MVP.
- 2 fichas diferidas hasta después del MVP.
- 1 hallazgo descartado por decisión de producto.
- 1 ficha de backups permanece en exploración únicamente por dos decisiones operativas aplazadas durante validación: proveedor/región y tiempo máximo de restauración.

## Prioridad crítica

- [Endurecimiento del acceso al VPS de producción](./secure-production-host-access.md)
- [Firma de confianza para APK de producción](./trusted-production-apk-signing.md)
- [Copias de seguridad automatizadas, cifradas y restaurables](./resilient-production-backups.md)
- [Cadena de despliegue de producción verificable](./trusted-production-deployments.md)

## Prioridad alta

- [Límites de abuso y coste por endpoint](./endpoint-abuse-and-cost-controls.md)
- [Revocación de sesiones al cambiar la contraseña](./password-reset-session-revocation.md)
- [Cabeceras web y origen seguro del panel admin](./web-and-admin-origin-hardening.md)
- [Actualización de dependencias con avisos de seguridad](./runtime-dependency-remediation.md)
- [Proveniencia y análisis de la cadena de suministro](./software-supply-chain-controls.md)
- [Endurecimiento de contenedores](./container-runtime-hardening.md)
- [Saneamiento de errores públicos de IA y STT](./public-ai-error-sanitization.md)
- [Borrado y retención real de chats y transcripciones](./chat-and-transcript-lifecycle.md)

## Prioridad media

- [Respuestas de autenticación resistentes a enumeración](./authentication-anti-enumeration.md)
- [Política de red segura en móvil](./mobile-secure-network-policy.md)
- [Formulario de acceso sin credenciales demo](./production-auth-form-hygiene.md)
- [Caché móvil privada y aislada por usuario](./private-mobile-user-cache.md)
- [Cierre de sesión remoto desde móvil](./mobile-remote-logout.md)
- [Entrega confiable de actualizaciones móviles](./trusted-mobile-update-delivery.md)

## Prioridad de compatibilidad y privacidad

- [Declaración de uso del micrófono en iOS](./ios-microphone-purpose-declaration.md)

## Hallazgos descartados por decisión de producto

- [Protección de capturas, grabaciones y vistas recientes](./sensitive-screen-privacy.md): no se aplicará protección de pantalla.

## Diferidas hasta después del MVP

- [Invalidación inmediata de sesiones globales](./immediate-global-session-invalidation.md): se acepta una ventana residual máxima de 15 minutos para access tokens ya emitidos.
- [Uso consentido de chats para mejorar modelos](./consented-chat-model-improvement.md): durante el MVP no se usarán chats para entrenar o mejorar modelos; solo se permite acceso limitado para corregir bugs.
- Controles avanzados incluidos en fichas ya definidas: SBOM/attestations/firma de contenedores, filesystem de solo lectura, endurecimiento adicional de PostgreSQL y certificate pinning.

## Decisiones transversales pendientes

- Definir propietarios operativos y objetivos medibles para backups, alertas, rotación de secretos y respuesta ante abuso.
- Aprobar umbrales de rate limiting y presupuesto sin perjudicar redes compartidas ni accesibilidad.
- Validar con asesoría jurídica y una EIPD/DPIA el uso secundario de chats o datos nutricionales para mejorar modelos.
- Confirmar la política de retención y borrado que verá el usuario; el contenido cacheado se eliminará al cerrar sesión.
- Seleccionar almacenamiento externo y objetivos de recuperación cuando la fase de validación justifique esa operación.
