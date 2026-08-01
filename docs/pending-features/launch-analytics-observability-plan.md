# Plan de analítica, observabilidad y preparación del lanzamiento

- Estado: En exploración
- Última actualización: 2026-07-22
- Superficies afectadas: landing web, Android/iOS, backend, panel admin, PostgreSQL, NGINX, CI/CD y operaciones
- Horizonte propuesto: preparación de 2 semanas, beta instrumentada de 2–4 semanas y lanzamiento público posterior
- Presupuesto objetivo inicial: 0–20 € al mes, más las tasas opcionales de las tiendas

## Resumen ejecutivo

Better Calories no necesita una única herramienta que intente resolverlo todo. Necesita separar cuatro preguntas distintas:

| Pregunta | Fuente de verdad recomendada |
| --- | --- |
| ¿De dónde viene el tráfico y qué hace en la web? | Umami |
| ¿El usuario se registra, obtiene valor y vuelve? | Datos de dominio + telemetría propia ya implementada, con agregaciones selectivas |
| ¿Está sano el servidor y por qué falla? | Grafana OSS, Prometheus, Loki y Alloy en el VPS, más un monitor externo mínimo |
| ¿Qué error sufrió una versión concreta? | Telemetría propia + logs correlacionados en Loki; crash reporting simbolicado se difiere |

La propuesta mínima para no lanzar a ciegas es:

1. **Umami autohospedado** para tráfico web, campañas UTM, CTA y descarga de la APK.
2. **Reutilizar la plataforma de telemetría propia que ya existe en el código actual**. El flujo móvil → API → PostgreSQL → panel admin está implementado y probado; el backend registra peticiones, trazas, acciones, conversaciones, búsquedas, voz, LLM y costes. Para lanzamiento no hace falta otra plataforma de analítica de producto: hace falta confirmar que toda la vertical está desplegada, completar unos pocos eventos de intención y construir agregaciones de activación/retención sobre datos autoritativos. No se debe enviar información nutricional ni conversaciones a una plataforma de marketing.
3. **Grafana OSS + Prometheus + Loki + Alloy en el VPS actual** para métricas, logs, paneles y alertas. Se acepta que esta pila no podrá avisar de una caída total del host a cambio de reducir cuentas y operación externa.
4. **Diferir GlitchTip** durante la beta. La telemetría propia y los logs de Loki cubrirán inicialmente los errores; se reconsiderará crash reporting simbolicado cuando aparezca una necesidad real que esas fuentes no resuelvan.
5. **Google Search Console y Bing Webmaster Tools** para impresiones, consultas, indexación, Core Web Vitals y tráfico orgánico que todavía no ha llegado a la web.
6. **restic + Backblaze B2** para copias cifradas fuera del VPS y una prueba real de restauración.
7. **listmonk + un proveedor SMTP** solo cuando exista una captación de correo con consentimiento; no es un bloqueador para instrumentar la beta.

Con este conjunto, el coste recurrente de software puede mantenerse en **0 € durante una beta pequeña**. El coste principal será la capacidad y operación del VPS, no las licencias.

La recomendación importante es no invertir todavía en PostHog, Matomo, Metabase, un clúster completo de observabilidad o píxeles publicitarios. Primero hay que demostrar que el embudo básico se mide de extremo a extremo y que la activación y la retención justifican esa complejidad.

## Problema y motivación

Ahora mismo se pueden investigar con bastante detalle peticiones, acciones y flujos técnicos de usuarios autenticados. Lo que todavía no se puede responder de forma directa y reproducible son varias preguntas de lanzamiento:

- cuántas personas descubren Better Calories;
- desde qué campaña, buscador, creador o comunidad llegan;
- cuántas visitan la página de descarga y cuántas pulsan la APK;
- cuántas completan un alta real, configuran el producto y registran su primera comida;
- dónde abandonan;
- cuántas vuelven al día siguiente o durante la primera semana;
- cuánto cuesta conseguir un usuario activado;
- si una caída, un error móvil o una degradación está afectando a la conversión;
- si las copias de seguridad permitirían recuperar el servicio.

Sin estas señales, es fácil optimizar visitas o descargas que no se convierten en uso real, gastar en canales sin retorno o enterarse tarde de una incidencia.

## Contexto actual verificado

### Capacidades ya existentes

- La landing es estática, se sirve desde NGINX y ya incluye `robots.txt`, `sitemap.xml`, metadatos sociales, datos estructurados y una página de descarga de APK. Véase [apps/landing](../../apps/landing/README.md).
- La API tiene entornos de desarrollo y producción, healthcheck y despliegue blue/green con comprobación antes y después del cambio. Véanse [compose.yml](../../infra/deploy/compose.yml) y [deploy.sh](../../infra/deploy/deploy.sh).
- El VPS medido dispone de 4 vCPU y 8,25 GB de RAM; los backends activos consumían unos 50–55 MiB en reposo. Véase [container-runtime-hardening.md](../container-runtime-hardening.md).
- El backend registra automáticamente cada petición `/v1/*`, excepto el healthcheck, como `backend.api_request_completed` o `backend.api_request_failed`. Conserva `traceId`, usuario cuando está autenticado, ruta, método, estado, duración, versión/build/plataforma/locale y sesión de cliente. Véase [app.ts](../../apps/backend/src/http/app.ts).
- Flutter ya dispone de una cola best-effort hacia `POST /v1/telemetry/client-events`, con lotes de hasta 50 eventos, buffer en memoria de 200, reintento, flush cada 30 segundos, sesión, versión, build y plataforma. Véase [client_telemetry_service.dart](../../apps/mobile/lib/data/services/client_telemetry_service.dart).
- La instrumentación móvil efectiva emite `mobile.api_request_failed`, `mobile.cache_write_failed`, `mobile.food_search_completed`, `mobile.food_search_failed`, `mobile.voice_recording_start_failed`, `mobile.voice_recording_stop_failed`, `mobile.voice_transcription_failed` y `mobile.voice_meal_run_failed`.
- El backend tiene telemetría especializada para búsquedas, STT, comidas por voz, ejecuciones LLM, turnos de agente, llamadas a herramientas, llamadas a proveedor, tokens, costes y transcripciones. Véanse [service.ts](../../apps/backend/src/telemetry/service.ts) y [telemetryService.ts](../../apps/backend/src/telemetry/telemetryService.ts).
- Las mutaciones de producto ya dejan una fuente autoritativa en `action_calls`, `audit_events`, tablas de comidas/propuestas y `user_food_feedback_events`; por ejemplo, commit, corrección y error no necesitan inferirse únicamente desde eventos móviles.
- PostgreSQL contiene las tablas especializadas `telemetry_events`, `llm_runs`, `food_search_events`, `agent_turn_telemetry`, `agent_tool_call_telemetry`, `llm_provider_calls` y `transcription_records`, además de conversaciones/mensajes y las tablas de dominio. Véanse [0017_telemetry_foundation.sql](../../infra/db/drizzle/0017_telemetry_foundation.sql) y [0019_admin_telemetry_vertical_slice.sql](../../infra/db/drizzle/0019_admin_telemetry_vertical_slice.sql).
- El panel admin ya ofrece overview, eventos, ejecuciones LLM, conversaciones, turnos, llamadas de acciones, coste LLM, proveedores, transcripciones, búsquedas y reconstrucción por `traceId`. La interfaz está protegida por credenciales propias y JWT con scope de lectura; el NGINX versionado sirve la UI estática bajo el entorno dev y esta puede apuntar solo a orígenes explícitamente permitidos. Véanse [adminTelemetry.ts](../../apps/backend/src/http/adminTelemetry.ts), [index.html](../../apps/admin/index.html) y [adminService.ts](../../apps/backend/src/auth/adminService.ts).
- Los textos de entrada/salida de `agent_turn_telemetry` y las transcripciones se redactan antes de insertarlos; las queries de búsqueda se sustituyen por hash y longitud. El metadato genérico tiene límites y saneamiento de claves sensibles. Esto no cubre automáticamente conversaciones de producto, argumentos/resultados de tools ni `action_calls`, que siguen su propio ciclo de vida.
- Los datos de diagnóstico sensibles tienen una política de borrado o saneamiento de 30 días. Véase [chat-transcript-lifecycle.md](../chat-transcript-lifecycle.md).
- Los dumps PostgreSQL se rotan a 30 días, pero siguen en el mismo host. La replicación fuera del VPS y la recuperación ante desastre siguen pendientes.
- El checkout principal contiene trabajo local en curso para reforzar la descarga y la información de privacidad. Ese trabajo todavía no incorpora la descripción completa de analítica, proveedores, conservación y derechos que exigirá el lanzamiento.

### Auditoría de cobertura de la telemetría propia

| Área | Estado | Fuente actual | Conclusión para el lanzamiento |
| --- | --- | --- | --- |
| Peticiones API y errores HTTP | Implementado | `telemetry_events` + middleware de Hono | Reutilizar; añadir agregados/alertas, no otro tracker |
| Correlación móvil/backend | Implementado | `X-Request-Id`, `traceId`, sesión y metadatos de build | Reutilizar como columna vertebral de diagnóstico |
| Fallos móviles conocidos | Parcial | `ClientTelemetryService` y ocho familias efectivas de eventos | Completar solo intenciones, vistas y abandonos críticos |
| Búsqueda y resolución de alimentos | Implementado | `food_search_events`, feedback y errores de proveedor | Reutilizar; ya permite cero resultados y baja confianza |
| Voz y STT | Implementado | eventos start/completed/failed + `transcription_records` | Reutilizar; no duplicar en una plataforma externa |
| Agente, tools y conversaciones | Implementado | conversaciones, `llm_runs`, turns, tool calls y action calls | Reutilizar; el panel ya reconstruye el trace |
| Tokens y coste LLM | Implementado | `llm_provider_calls` + vista de coste | Reutilizar; falta cruzarlo con comidas/activados |
| Alta de usuario | Parcial pero derivable | `users`, peticiones auth y `audit_events` | Normalizar una vista; distinguir alta nueva de login Google |
| Primera comida y correcciones | Implementado como dominio | `meals`, propuestas, `action_calls` y food feedback | Derivar desde filas consumadas, no desde evento cliente |
| Configuración inicial | Sin definición única | goals/settings; no hay onboarding formal | Acordar el hito antes de instrumentarlo |
| Retención D1/D7/D30 | Datos base disponibles, agregado ausente | usuarios + comidas/actividad significativa | Crear vistas/cohortes SQL y panel ejecutivo |
| Adquisición web/UTM | No implementado | — | Añadir Umami; está fuera del alcance de la telemetría app |
| Métricas de host/logs/uptime | No implementado de extremo a extremo | healthcheck y logs locales | Añadir Grafana/Alloy y monitor externo |
| Crash reporting simbolicado | No implementado | errores funcionales propios, sin stack traces por release | Diferir; medir primero si telemetría propia + Loki son insuficientes |

La conclusión de la auditoría es que **no se debe introducir PostHog ni reconstruir la analítica de producto desde cero**. La plataforma propia ya es la fuente correcta para el producto autenticado y los datos sensibles. El trabajo restante consiste en normalizar fuentes que ya existen, cubrir los pocos hitos que solo conoce la UI y añadir vistas agregadas para negocio.

### Carencias confirmadas

- No hay analítica de la landing ni catálogo de eventos web.
- No existe una convención UTM compartida.
- No se puede unir una visita web a una instalación obtenida mediante APK directa.
- El panel actual es principalmente operativo y de investigación por usuario/trace; no calcula un embudo de alta → configuración → primera comida ni cohortes D1/D7/D30.
- No existe un evento explícito de onboarding porque la app tampoco tiene hoy un flujo único denominado onboarding; deberá definirse qué hecho de dominio representa «configuración completada».
- Faltan eventos móviles de intención o presentación que el servidor no puede observar: inicio de registro, pantalla/CTA relevante, inicio de registro de comida, propuesta mostrada y abandono.
- La cola móvil no es persistente: un cierre de la app descarta lo pendiente. El endpoint requiere autenticación, por lo que no sirve para adquisición anónima y un evento previo al login solo podría entregarse más tarde si permanece en memoria.
- `telemetry_events` no tiene `event_id` idempotente ni `schema_version`; una respuesta perdida seguida de reintento puede duplicar eventos móviles. No se usará esta tabla como fuente única de conversiones consumadas hasta resolverlo.
- `audit_events` contiene señales de autenticación útiles (`auth.email_confirmed`, login y entrega de email), pero no tiene vista propia en el panel. Algunas filas incluyen email en metadata y usan trazas constantes como `auth-register` en vez del `traceId` real de la petición; requieren minimización y mejor correlación independientes de la redacción aplicada por `TelemetryService`.
- La eliminación de cuenta borra tablas de telemetría y `action_calls`, pero `audit_events` usa `ON DELETE SET NULL`; cualquier email conservado en su metadata puede sobrevivir sin `user_id`. Debe eliminarse ese dato de nuevas escrituras y sanearse el histórico antes del lanzamiento amplio.
- El middleware también registra las consultas del propio panel y los POST de ingestión. Es útil operativamente, pero `totalEvents` y `uniqueTraces` incluyen tráfico del observador; los KPI de producto deben excluir rutas `/v1/admin/telemetry/*` y el overhead de `/v1/telemetry/client-events`.
- `action_calls` y los argumentos/resultados de tools permiten una investigación detallada pero pueden contener datos nutricionales. Los tools se sanean tras 30 días; `action_calls` no participa en ese saneamiento periódico. Hace falta justificar su retención, minimizar payloads o definir un agregado seguro.
- El README del panel admin describe solo la primera vertical y está desactualizado frente a las once vistas que realmente contiene la interfaz.
- No hay monitor externo que siga funcionando si cae el VPS.
- No hay pipeline central de métricas y logs con alertas.
- No hay seguimiento dedicado de excepciones y crashes por release.
- No hay copia cifrada y verificada fuera del servidor.
- No hay una rutina ejecutiva que combine adquisición, producto, fiabilidad y coste.

## Qué se puede y qué no se puede medir

La frase «quién entra y quién no entra» necesita una precisión importante:

- Umami puede medir de forma anónima las visitas que llegan, su procedencia, dispositivo, país, campaña y acciones en la landing.
- Search Console, Bing y cada plataforma de campaña pueden medir **impresiones o alcance agregados**, es decir, personas a las que se mostró un resultado o contenido aunque no visitaran la web.
- Ninguna herramienta web puede identificar legítimamente a cada persona que vio una publicación y decidió no visitar la web.
- Con una APK descargada directamente no existe un mecanismo estándar para transportar el UTM desde el navegador hasta la primera apertura. La relación `campaña → instalación → registro` será aproximada hasta distribuir mediante una tienda o introducir otro mecanismo explícito.
- No se debe resolver ese hueco mediante fingerprinting. Durante la beta se usarán datos agregados y, opcionalmente, una pregunta de procedencia declarada por el usuario.

El cuadro de mando de marketing debe combinar:

```text
impresiones del canal
  -> clics declarados por el canal
  -> sesiones medidas por Umami
  -> apertura de la página de descarga
  -> clic en descargar APK
  -> registros en backend (aproximación agregada durante la APK directa)
  -> configuración inicial completada (cuando se defina el hito)
  -> primera comida registrada
  -> usuario retenido D1 / D7 / D30
```

## Objetivos

### Objetivo principal

Poder decidir cada semana qué mejorar y dónde invertir usando un embudo reproducible desde adquisición hasta retención, acompañado de señales fiables de salud técnica y coste.

### Objetivos operativos

- Detectar una caída total de landing o API desde fuera del VPS en un máximo objetivo de diez minutos.
- Conocer el canal y campaña de cada sesión web sin recopilar PII.
- Medir el paso de landing a descarga, y de registro a primera comida.
- Medir activación, abandono y cohortes D1/D7/D30 con eventos de negocio autoritativos.
- Correlacionar errores de producto, logs y excepciones mediante release, entorno y `traceId`.
- Conocer coste de LLM/STT por comida registrada y por usuario activado.
- Recuperar producción desde una copia cifrada fuera del VPS siguiendo un runbook probado.
- Mantener el coste de herramientas dentro del nivel gratuito o de una suscripción pequeña mientras el volumen lo permita.

## Fuera de alcance inicial

- Identificar personalmente a visitantes anónimos de la web.
- Session replay, heatmaps o grabaciones de pantalla.
- Meta Pixel, Google Ads remarketing u otros rastreadores publicitarios antes de resolver consentimiento y necesidad real.
- Unificar PII, nutrición, conversaciones y marketing en un perfil de usuario externo.
- Autohospedar Sentry/GlitchTip, Tempo, Mimir, PostHog o un clúster distribuido de observabilidad en el VPS de producción.
- Construir un data warehouse, CDP o lago de datos.
- Crear objetivos de conversión permanentes antes de obtener una línea base real de 2–4 semanas.
- Tomar aperturas de correo como KPI principal; son poco fiables. Se priorizarán entrega, clic y activación.

## Métrica norte y embudo

### Métrica norte provisional

**Usuarios activados semanalmente:** usuarios nuevos que registran al menos tres comidas en dos días distintos durante sus primeros siete días.

Esta definición evita declarar «éxito» por una visita, una descarga o un registro sin uso. Debe revisarse tras observar a los primeros 30–50 usuarios reales.

### Evento de activación temprana

La primera señal de valor será `meal_log_committed`: una comida guardada correctamente. También se medirá el tiempo desde registro hasta esa primera comida.

### Métricas por etapa

| Etapa | Métricas mínimas | Fuente |
| --- | --- | --- |
| Alcance | impresiones, consultas, posición, alcance del contenido, gasto | Search Console, Bing y plataformas de campaña |
| Adquisición | sesiones, visitantes, fuente/medio/campaña, landing, dispositivo | Umami |
| Interés | profundidad útil, visita a descarga, CTA, FAQ relevante | Umami |
| Descarga | clic en APK, versión ofrecida, errores de descarga | Umami, NGINX y sintéticos |
| Registro | solicitudes, confirmación de email, altas Google nuevas, errores | peticiones API + `users` + `audit_events` |
| Activación | configuración inicial acordada, primera comida, tiempo a primer valor | tablas de dominio + eventos móviles selectivos |
| Uso | comidas por usuario activo, voz/texto, propuesta confirmada/editada | `meals` + `action_calls` + telemetría especializada |
| Retención | D1, D7 y D30 por cohorte y por versión | vistas agregadas sobre datos propios |
| Calidad | correcciones, abandonos, búsquedas sin resultado, errores de agente | panel admin existente |
| Fiabilidad | disponibilidad, p95, 5xx, errores, reinicios, disco, backup | Grafana + telemetría propia + monitor externo |
| Economía | gasto de canal, CAC por activado, LLM/STT por comida/activado | hoja de campaña + panel admin |

No se fijarán tasas objetivo definitivas en este documento. Durante las primeras 2–4 semanas se establecerá la línea base, se comprobarán los denominadores y después se fijarán objetivos trimestrales.

## Arquitectura recomendada

```text
Visitante web
  -> bettercalories.app
     -> Umami: páginas, UTM y eventos web anónimos
     -> Search Console/Bing: impresiones, consultas e indexación

Usuario móvil
  -> CalTrackerApiClient: X-Request-Id + build/plataforma
  -> ClientTelemetryService autenticado: fallos e interacción selectiva
     -> API Better Calories
        -> middleware: todas las peticiones /v1 salvo health
        -> servicios especializados: búsqueda, voz, agente, tools y proveedores
        -> tablas de dominio: usuarios, comidas, propuestas, acciones y auditoría
           -> PostgreSQL + panel admin: diagnóstico, producto, LLM/STT y costes
           -> vistas nuevas: activación y cohortes

Landing / NGINX / backend / PostgreSQL / Docker / host
  -> Grafana Alloy
     -> Prometheus local: métricas
     -> Loki local: logs
        -> Grafana OSS local: paneles y alertas

Monitor HTTP gratuito, desde fuera del VPS
  -> landing, API, manifiesto APK, certificado y flujo crítico

Backups locales
  -> restic, cifrado en cliente
     -> Backblaze B2, fuera del VPS
```

### Topología de red y exposición

«VPS», «VPN» y «certificado» no son alternativas equivalentes. Para el lanzamiento se elige el VPS actual y no se añade una VPN:

- el **VPS** ejecuta servicios;
- **TLS/HTTPS** cifra y autentica el dominio, pero no decide por sí solo quién puede entrar;
- un **túnel SSH** cifra y restringe las superficies administrativas sin introducir otro servicio de red.

La arquitectura propuesta divide el sistema en tres zonas:

```text
Internet
  -> NGINX :80/:443 + certificados Let's Encrypt
     -> PÚBLICO: landing, API, descarga, health mínimo
     -> PÚBLICO LIMITADO: script y collector de Umami
     -> nunca: PostgreSQL, Docker API, Alloy UI o dashboards internos

Túnel SSH con clave, sin publicar nuevos puertos
  -> PRIVADO: panel admin Better Calories
  -> PRIVADO: dashboard/login de Umami
  -> PRIVADO: Grafana OSS
  -> PRIVADO: Prometheus, Loki y UI de Alloy
  -> PRIVADO: administración futura de listmonk

Solo salida HTTPS/TLS desde el VPS
  -> Backblaze B2
  -> monitor HTTP externo
  -> proveedor SMTP
```

#### Aplicación al despliegue actual

- Mantener NGINX como único punto de entrada HTTP. Los nuevos contenedores publicarán como máximo en `127.0.0.1`; NGINX será el único proxy hacia ellos.
- Mantener PostgreSQL sin `ports` públicos, como ya hace el Compose. Umami tendrá base y rol propios aunque comparta inicialmente el motor.
- Emitir y renovar certificados Let's Encrypt para cada hostname público. Grafana y los dashboards internos no necesitarán hostname público: se accederá a sus puertos de loopback mediante túnel SSH.
- Mantener UFW con solo SSH y HTTP/HTTPS; no abrir `3000`, `9090`, `3100`, `12345` ni `5432` a Internet.
- Conservar autenticación de aplicación además del túnel: JWT admin para Better Calories, contraseña fuerte para Umami y login de Grafana. SSH no reemplaza autorización ni auditoría.
- No añadir WireGuard, mTLS, Alertmanager, Mimir ni Tempo durante la beta. Se reconsiderarán únicamente si aparecen varios operadores, más hosts o una necesidad que Grafana Alerting no cubra.

#### Exposición por herramienta

| Componente | Ubicación inicial | Entrada pública | Administración | Motivo |
| --- | --- | --- | --- | --- |
| Umami | VPS actual, contenedor aislado | Solo tracker y endpoint de recogida por HTTPS | Túnel SSH + login | El navegador del visitante debe poder enviar eventos, el dashboard no |
| Panel admin propio | VPS actual | Ninguna | Túnel SSH + JWT admin | Contiene trazas y datos internos sensibles |
| Grafana OSS | VPS actual | Ninguna | Túnel SSH + login | Paneles y alertas sin una cuenta externa |
| Prometheus | VPS actual | Ninguna | Red Docker/loopback | Almacén local de métricas con retención limitada |
| Loki monolítico | VPS actual | Ninguna | Red Docker/loopback | Almacén local de logs con límites estrictos de disco |
| Grafana Alloy | VPS actual | Ninguna | Red Docker/loopback | Recoge host, contenedores y logs y los envía a Prometheus/Loki locales |
| Sintéticos | Servicio externo | Consulta health/landing públicos | Dashboard externo con MFA | Un monitor dentro del VPS no detecta la caída del propio host |
| restic/B2 | Cliente local + objeto externo | Ninguna entrada | Credenciales de bucket limitadas; solo salida HTTPS | El backup debe sobrevivir a pérdida del VPS |
| listmonk futuro | VPS o SaaS posterior | Formularios, confirmación y baja estrictamente necesarias | Túnel SSH | Separar endpoints de destinatario del panel de campañas |

En Umami no se puede poner toda la instancia detrás del túnel: el tracker de la landing necesita cargar el script y enviar a su endpoint de recogida. NGINX expondrá únicamente esas rutas y bloqueará el dashboard, login y API administrativa desde Internet. Si separar rutas por versión resultase frágil, se usarán dos hostnames hacia el mismo upstream: collector público y administración privada.

Se acepta conscientemente que Grafana, Prometheus y Loki compartirán destino con el sistema vigilado. Detectarán degradaciones parciales, errores y agotamiento de recursos, pero no podrán avisar de una caída total del VPS. Esa carencia se cubre con una única comprobación HTTP externa gratuita; no se añade otra plataforma completa.

El mini-PC y Grafana Cloud quedan como alternativas futuras, no como dependencias del lanzamiento.

### Fronteras de datos

| Destino | Datos permitidos | Datos prohibidos |
| --- | --- | --- |
| Umami | URL saneada, UTM, CTA, dispositivo, país aproximado | email, UUID de usuario, texto libre, comida, transcript, query sensible |
| Grafana | métricas agregadas, logs saneados, `traceId`, release | tokens, cookies, audio, transcript, cuerpos de petición, email |
| Crash reporting futuro | excepción, stack trace, release, plataforma, pseudónimo opcional | credenciales, cuerpos completos, datos nutricionales, mensajes de chat |
| Telemetría propia | eventos técnicos/producto, UUID interno, estado, duración y datos de dominio sujetos a la política interna | audio; duplicar texto bruto en eventos genéricos; PII no necesaria para la métrica |
| listmonk | email, consentimiento, lista y campaña | datos de salud, comidas, chats, telemetría técnica |

## Selección de herramientas

| Necesidad | Elección inicial | Motivo | Alternativa o evolución |
| --- | --- | --- | --- |
| Analítica web | Umami autohospedado | Open source, sin cookies, eventos, funnels y UTM; encaja con la landing estática | Umami Cloud Hobby si se prioriza cero operación |
| Analítica de producto | Telemetría propia existente | Ya está correlacionada con usuarios, acciones, LLM y privacidad | Metabase sobre vistas agregadas cuando haga falta análisis ad hoc |
| Métricas/logs/alertas | Grafana OSS + Prometheus + Loki + Alloy | Todo en Compose sobre el VPS; Grafana Alerting evita desplegar Alertmanager | Grafana Cloud si operar la pila local consume demasiado tiempo |
| Excepciones/crashes | Diferido | La telemetría propia y Loki cubren el lanzamiento sin otro servicio | GlitchTip/Sentry cuando hagan falta símbolos y agrupación de crashes |
| Uptime | UptimeRobot Free | Única excepción operativa necesaria; admite checks HTTP cada 5 minutos para una beta comercial pequeña | Proveedor diferente o segundo host cuando aumente la criticidad |
| Backups externos | restic + Backblaze B2 | Cifrado en cliente, herramienta open source y almacenamiento muy barato | Otro objeto S3-compatible con región y contrato adecuados |
| SEO | Search Console + Bing Webmaster | Datos de impresiones, consultas, índice y problemas que Umami no ve | Ninguna herramienta de pago es necesaria al inicio |
| Newsletter | listmonk + SMTP | AGPL, ligero, double opt-in, bajas y analítica de campaña | Proveedor SaaS barato si la operación de correo consume demasiado tiempo |
| Estado público | Diferido | No es imprescindible para una beta pequeña | Uptime Kuma externo o página estática separada |

### Herramientas que no se recomiendan todavía

- **PostHog:** excelente para experimentación, funnels y feature flags, pero duplica parte de Umami y la telemetría propia, añade coste operativo y aumenta el riesgo de capturar datos sensibles.
- **Matomo:** válido, pero más pesado y con más superficie de configuración de privacidad para las necesidades actuales.
- **Metabase:** útil cuando haya preguntas de negocio frecuentes que no pueda responder el panel admin; no es un sustituto de la instrumentación.
- **Tempo, Mimir y Alertmanager:** no se necesitan para un único VPS; Grafana Alerting, Prometheus y Loki cubren la beta con menos procesos.
- **Google Analytics 4:** no aporta una ventaja suficiente frente a Umami en esta fase y complica privacidad, consentimiento y gobernanza.

## Plan de trabajo por frente

### 1. Gobierno de medición

Crear antes de instrumentar:

- un propietario para crecimiento, producto, operaciones y privacidad, aunque una misma persona desempeñe varios roles;
- un diccionario de eventos versionado;
- definición, numerador, denominador, ventana temporal y fuente de cada KPI;
- convención de nombres en `snake_case` y pasado para eventos consumados;
- separación de `dev` y `prod` en todos los proveedores;
- presupuesto mensual y alertas al 50 %, 80 % y 100 % de cuota;
- calendario de conservación y borrado por sistema;
- registro de cambios de instrumentación para no comparar series incompatibles.

Cada evento nuevo deberá indicar:

```text
nombre
versión de esquema
product owner
momento exacto de emisión
fuente autoritativa
propiedades permitidas
PII prohibida
retención
tests
dashboard que lo consume
```

### 2. Umami para web y campañas

#### Despliegue

- Servir Umami en `analytics.bettercalories.app` mediante HTTPS.
- Usar una imagen fijada por versión o digest; no `latest` en producción.
- Crear base de datos y rol PostgreSQL exclusivos para Umami. Puede compartir el motor PostgreSQL del VPS al inicio, pero no la base, schema ni credenciales de la aplicación.
- Mantener dashboard y administración protegidos; solo el collector debe ser público.
- Definir healthcheck, reinicio, límites de recursos, backup, actualización y rollback.
- Probar primero en desarrollo y observar CPU, RAM, disco y crecimiento de tablas durante al menos 24 horas.
- Activar `DISABLE_TELEMETRY=1`, considerar `PRIVATE_MODE=1` y cambiar todas las credenciales iniciales.
- Incluir Umami en la copia externa y probar recuperación de su base.

#### Integración en la landing

- Cargar el tracker solo en `bettercalories.app` y `www.bettercalories.app`; excluir localhost, dev y admin mediante `data-domains`.
- Respetar `Do Not Track` con `data-do-not-track="true"`.
- Actualizar CSP para permitir únicamente el script y collector necesarios y ampliar las pruebas de política web.
- Sanear la query antes de enviarla: conservar solo `utm_source`, `utm_medium`, `utm_campaign`, `utm_content` y `utm_term`; eliminar cualquier otro parámetro.
- No usar `umami.identify`, Distinct IDs ni event properties con email o UUID.
- Desactivar session replay y heatmaps en el lanzamiento.
- Mantener Core Web Vitals habilitado solo si la revisión de privacidad aprueba la configuración y volumen.

#### Eventos web mínimos

| Evento | Momento | Propiedades permitidas |
| --- | --- | --- |
| `download_page_opened` | navegación a `/download.html` | `cta_location`, `variant` |
| `apk_download_clicked` | clic real en `latest.apk` | `cta_location`, `apk_channel`, `variant` |
| `how_it_works_clicked` | clic desde hero a explicación | `cta_location`, `variant` |
| `faq_opened` | apertura de una pregunta útil | `faq_id` cerrado, nunca texto libre |
| `newsletter_signup_succeeded` | alta confirmada, si se añade | `form_location`; nunca email |
| `store_badge_clicked` | cuando exista tienda | `store`, `cta_location` |

Los eventos deben probarse con bloqueadores, JavaScript desactivado y navegación rápida. NGINX seguirá siendo una segunda fuente agregada para descargas aunque el tracker esté bloqueado.

#### Retención y privacidad

- Documentar la finalidad estricta de medición de audiencia.
- Configurar o automatizar el borrado para no superar la ventana aprobada. Como máximo de referencia, la guía de la AEPD contempla 25 meses para información de medición exenta; Better Calories debería empezar con 13 meses salvo necesidad demostrada.
- Informar de la medición en la política de privacidad aunque no se use cookie.
- Verificar de forma legal y técnica que la configuración elegida puede operar sin consentimiento. «Sin cookies» no elimina automáticamente todas las obligaciones.

### 3. Analítica de producto sobre la base existente

La fuente de verdad para una conversión consumada será la fila de dominio que demuestra que ocurrió. `telemetry_events` se reservará para contexto técnico, intención y presentación; no se duplicará una comida o un alta en otra plataforma solo para poder contarlas.

#### Inventario de hitos y trabajo restante

| Hito analítico | Evidencia actual | Estado | Acción propuesta |
| --- | --- | --- | --- |
| Solicitud de alta | petición `/v1/auth/register` + `auth.email_confirmation_requested` | Existe, pero el endpoint responde de forma neutral | Contar intentos agregados sin interpretar cada 200 como alta nueva |
| Alta email completada | fila nueva en `users` + `auth.email_confirmed` | Implementado; audit sin trace real | Exponer una vista saneada y mejorar correlación para calcular tiempo desde solicitud |
| Alta Google nueva | `users.created_at` + `auth.google_login_succeeded` | Derivable, no explícito | Distinguir en servidor o vista `new_user` frente a login existente |
| Configuración inicial | goals/settings | Sin definición de producto | Decidir si el hito es objetivo calórico configurado u otro hecho; después derivarlo |
| Registro de comida iniciado | estado de UI | No observable por backend | Añadir `mobile.meal_log_started` |
| Propuesta mostrada | estado de UI + propuesta ya creada en backend | Parcial | Añadir `mobile.meal_proposal_viewed` correlacionado por `traceId`/proposal ID pseudónimo |
| Comida guardada | `meals`, `action_calls`, propuesta y feedback `proposal_committed` | Implementado y autoritativo | Crear vista `meal_log_committed`; no emitir una conversión cliente duplicada |
| Comida corregida | comida/acción + feedback `proposal_corrected` | Implementado y autoritativo | Crear vista agregada de corrección |
| Grabación iniciada | estado de UI; hoy solo se emiten fallos | Ausente | Añadir `mobile.voice_recording_started` sin audio ni texto |
| Transcripción terminada | eventos STT/voice + `transcription_records` | Implementado | Reutilizar sin enviar transcript a terceros |
| Turno de agente terminado | `agent_turn_telemetry`, tools, provider calls y `llm_runs` | Implementado | Reutilizar y cruzar con el resultado de dominio |
| Flujo abandonado | propuesta sin commit o UI abandonada | Parcialmente derivable | Definir ventana y combinar vista backend + evento cliente del último paso |
| Retención significativa | actividad en `meals` por usuario y día | Derivable | Crear cohortes SQL D1/D7/D30 |
| Suscripción | no existe todavía | Futuro | Instrumentar desde store/backend cuando haya monetización |

#### Reglas

- No crear una tabla nueva si una vista sobre `users`, `meals`, `action_calls` o feedback ya demuestra el resultado.
- Usar IDs/constraints de las filas de dominio como idempotencia de conversiones consumadas.
- Añadir `event_id` idempotente y `schema_version` al contrato genérico antes de usar nuevos eventos móviles para contadores relevantes. El servidor debe deduplicar por usuario + `event_id`.
- Mantener `sessionId`, `appVersion`, `appBuild`, plataforma, locale, entorno y `traceId`.
- No enviar emails, nombres, ingredientes, cantidades, transcripciones ni texto escrito como propiedades analíticas.
- Derivar D1/D7/D30 desde filas de comidas consumadas, no desde una simple apertura ni desde entrega best-effort del móvil.
- Calcular activación y cohortes con consultas o vistas agregadas en PostgreSQL.
- Crear una capa de consultas/vistas de solo agregados y extender primero el overview del panel admin antes de introducir Metabase.
- Excluir tráfico admin/ingestión de los KPI y separar claramente «eventos técnicos» de «acciones de usuarios».
- Añadir al panel una vista saneada de altas; no exponer directamente el metadata histórico con email de `audit_events`.
- Eliminar email de los nuevos `audit_events`, sanear el histórico y cubrir la eliminación de cuenta con una prueba específica.
- Revisar la conservación de `action_calls` y evitar que una métrica agregada dependa de conservar indefinidamente inputs/outputs nutricionales.
- Ejecutar saneamiento y retención conforme a la política de 30 días para detalle crudo; conservar agregados sin PII durante el período aprobado.
- Añadir tests de contrato, deduplicación, auth, saneamiento, retención y ausencia de impacto en UX.
- Actualizar [apps/admin/README.md](../../apps/admin/README.md) para que describa las vistas y endpoints reales.

#### Paneles de producto

1. **Activación:** alta real → configuración acordada → primera comida → tres comidas en dos días.
2. **Retención:** D1/D7/D30 por cohorte, versión, plataforma y modo de primera comida.
3. **Calidad:** ampliar los paneles actuales con confirmación sin edición, corrección y abandono; conservar cero resultados y fallos de voz/agente ya disponibles.
4. **Coste:** partir de la vista de coste LLM existente y cruzarla por `traceId`/acción con comida guardada y usuario activado.

### 4. Grafana para operaciones

#### Estrategia

Desplegar una pila monolítica y acotada en el Compose del VPS:

- **Alloy** recoge métricas del host/contenedores y logs;
- **Prometheus** conserva las métricas localmente;
- **Loki** conserva los logs localmente con filesystem y modo monolítico;
- **Grafana OSS** consulta ambos y usa Grafana Alerting para enviar email/Telegram/webhooks, sin desplegar Alertmanager.

Grafana documenta Docker/Compose para evaluación y recomienda Helm o Tanka para despliegues Loki de producción de mayor escala. Para esta beta de un único VPS se acepta conscientemente Compose porque Kubernetes/Tanka añadirían más operación que resiliencia; la salida futura será migrar a un servicio gestionado o segundo host, no convertir este VPS en un clúster.

El VPS verificado tiene 4 vCPU y 8,25 GB de RAM. Antes de desplegar se medirá el disco libre y el consumo real de PostgreSQL. Presupuesto inicial de contenedores, sujeto a una prueba de carga:

| Servicio | Límite inicial de memoria | Retención inicial |
| --- | ---: | --- |
| Grafana | 512 MiB | configuración persistente |
| Prometheus | 1 GiB | 15 días, con límite de tamaño |
| Loki | 1 GiB | 7 días, con límite de ingestión |
| Alloy | 384 MiB | solo buffers locales |
| Umami | 512 MiB | según política de analítica |

La suma de límites nuevos es 3,4 GiB. No se desplegará la pila si, después de reservar sistema operativo, PostgreSQL, backends activos y margen de despliegue blue/green, la memoria o el disco quedan sin holgura suficiente.

Ningún contenedor de observabilidad recibirá el socket Docker bruto. Alloy obtendrá métricas del host con sus exporters y leerá únicamente las rutas de logs necesarias mediante montajes read-only. Las métricas por contenedor se añadirán solo mediante un exporter endurecido y permisos mínimos; no se debilitará `cap_drop`, `no-new-privileges` ni el aislamiento actual para completar un dashboard.

#### Métricas mínimas

- Host: CPU, memoria, load, disco, inodos, red y tiempo de actividad.
- Docker: estado, healthcheck, reinicios, CPU, memoria y OOM por contenedor.
- NGINX: peticiones, 2xx/4xx/5xx, latencia, bytes, hosts y upstream.
- Backend: tasa por ruta normalizada, p50/p95/p99, 4xx/5xx, concurrencia y errores por código estable.
- PostgreSQL: disponibilidad, conexiones, locks, tamaño, crecimiento, checkpoints y consultas lentas agregadas.
- Despliegue: versión/digest activo, resultado, duración y rollback.
- Backups: último éxito, antigüedad, tamaño, subida externa y último restore test.
- Certificados: días hasta expiración.
- Proveedores: disponibilidad, latencia y error rate de LLM/STT sin etiquetas de usuario.

Evitar etiquetas de alta cardinalidad: no usar `userId`, email, URL cruda, texto, `traceId` o IDs de comida como labels de Prometheus. El `traceId` sí puede aparecer en logs saneados y búsquedas puntuales.

#### Logs

- Emitir JSON estructurado con timestamp, nivel, servicio, entorno, release, ruta normalizada, status, duración y `traceId`.
- Redactar `authorization`, cookies, tokens, payloads, audio, transcripts y PII antes de salir del proceso.
- Configurar rotación del driver Docker y límites de ingestión/retención de Loki para que dos copias locales del mismo log no llenen el disco.
- Conservar inicialmente 7 días de logs y 15 días de métricas; ampliar solo después de medir el crecimiento diario.

#### Dashboards operativos

1. **Estado global:** landing, API dev/pro, PostgreSQL, contenedores y certificados.
2. **API:** tráfico, latencia, errores, rutas y releases.
3. **Host/Docker:** capacidad y presión de recursos.
4. **PostgreSQL:** conexiones, locks, crecimiento y backup.
5. **Proveedores:** LLM/STT, coste, latencia y fallos.
6. **Lanzamiento:** panel combinado con señales técnicas que puedan explicar una caída de conversión.

### 5. Crash reporting diferido

GlitchTip queda diferido para reducir servicios e integraciones. Durante la beta:

- los errores funcionales seguirán en la telemetría propia;
- Flutter y backend incluirán release/build y `traceId` en los eventos permitidos;
- los logs saneados llegarán a Loki y se correlacionarán desde Grafana;
- se medirá cuántos incidentes no pueden diagnosticarse por falta de stack trace simbolicado.

Se reabrirá esta decisión si los crashes nativos o las excepciones no reproducibles hacen insuficiente el diagnóstico actual. En ese momento se preferirá un servicio alojado antes que añadir Sentry/GlitchTip completo al mismo VPS.

### 6. Uptime, alertas e incidentes

#### Pruebas externas

Configurar en UptimeRobot Free y usar comprobación multiubicación cuando esté disponible:

- `GET https://bettercalories.app/` devuelve 200 y contiene una marca esperada.
- `GET https://api.bettercalories.app/v1/health` devuelve el contrato esperado.
- `GET https://dev-api.bettercalories.app/v1/health` se monitoriza con prioridad menor.
- `GET https://api.bettercalories.app/apk/latest.json` devuelve JSON válido, versión y SHA-256.
- `HEAD/GET` parcial de `latest.apk` devuelve tipo y tamaño razonables sin descargarlo entero cada minuto.
- El certificado TLS es válido y no caduca pronto.
- Una prueba de navegador poco frecuente valida landing → página de descarga → CTA visible.

#### Alertas iniciales

| Severidad | Condición | Acción |
| --- | --- | --- |
| P1 | producción caída confirmada por el monitor externo; pérdida de datos; restore bloqueado | notificación inmediata y runbook de incidente |
| P2 | 5xx > 3 % durante 10 min; p95 duplicado; backup > 26 h; disco > 85 % | investigar durante el día |
| P3 | cuota > 80 %; certificado < 21 días; errores nuevos no masivos | backlog priorizado |

Las alertas deben llegar al menos por dos vías, por ejemplo email y Telegram. Cada alerta tendrá propietario, enlace al dashboard, primer diagnóstico y acción de silencio. Se revisarán semanalmente para retirar ruido.

### 7. Backups y recuperación

- Mantener los dumps locales actuales como primera capa.
- Cifrar y subir diariamente producción y overlays de supresión a un bucket B2 privado mediante restic.
- Usar credenciales de escritura limitadas y una credencial separada para borrado/retención.
- Conservar la política de privacidad de 30 días para datos de usuario, también fuera del host.
- Monitorizar último backup local, subida externa, tamaño y edad.
- Probar restauración mensual en un entorno aislado, incluyendo migraciones, healthcheck y reaplicación del ledger de privacidad.
- Registrar RPO y RTO observados. Objetivo inicial propuesto: RPO ≤ 24 h y RTO ≤ 4 h.
- No declarar el backup «operativo» hasta completar una restauración desde B2.

### 8. SEO, descubrimiento y rendimiento web

- Verificar el dominio en Google Search Console y Bing Webmaster Tools mediante DNS.
- Enviar el sitemap y revisar indexación, rich results y Core Web Vitals.
- Comprobar que `/download.html` siga la decisión de indexación deseada; hoy está planteada como `noindex`.
- Añadir anotaciones de release de contenido para explicar cambios en impresiones y CTR.
- Crear contenido solo alrededor de problemas que Better Calories resuelve de verdad: registro por voz, corrección, comidas habituales, macros y procedencia nutricional.
- Priorizar páginas útiles y específicas antes que publicar artículos genéricos en volumen.
- Revisar semanalmente consultas con impresiones y CTR bajo para ajustar título, descripción y contenido.

### 9. Captación, email y feedback

No hace falta desplegar listmonk para medir la beta. Se añadirá cuando exista una propuesta clara para la lista: acceso anticipado, novedades de versión o contenido útil.

Requisitos antes de capturar correo:

- finalidad y consentimiento separados;
- double opt-in;
- fecha, fuente y versión del consentimiento;
- baja con un clic y lista de supresión;
- SPF, DKIM y DMARC;
- separación entre correo transaccional y marketing;
- procesamiento de rebotes y quejas;
- UTM en cada enlace de campaña;
- email nunca enviado como propiedad de Umami.

listmonk es AGPL, usa PostgreSQL y soporta double opt-in, bajas y webhooks de rebote. Amazon SES es barato, pero desde el 21 de julio de 2026 su plan Essentials publicado parte de 0,16 USD por 1.000 emails. Debe compararse con el proveedor transaccional que ya use el proyecto antes de añadir otra cuenta.

Para feedback cualitativo durante la beta se recomienda un enlace visible dentro de la app o en cada release que recoja:

- objetivo que intentaba cumplir;
- punto de fricción;
- si logró registrar la comida;
- valoración opcional;
- permiso separado para contacto.

No se debe mezclar el formulario de feedback con telemetría automática ni adjuntar conversaciones completas por defecto.

### 10. Privacidad, seguridad y cumplimiento

- Convertir la página informativa actual en una política completa con responsable, contacto, finalidades, base jurídica, categorías, proveedores, transferencias, conservación y derechos.
- Documentar Umami, el monitor externo, almacenamiento B2 y proveedor de email en el inventario correspondiente; Grafana/Prometheus/Loki permanecen en infraestructura propia.
- Revisar región de alojamiento, DPA y transferencias antes de producción.
- Realizar una evaluación documentada de la configuración de analítica conforme a la guía de medición de audiencia de la AEPD.
- Si una herramienta o finalidad exige consentimiento, cargarla solo después de una elección válida, con aceptar y rechazar al mismo nivel. Se puede usar una CMP open source como Klaro si llega ese momento.
- Prohibir publicidad basada en perfiles que use o infiera datos de salud o nutrición.
- Mantener secretos fuera del repositorio, rotarlos y limitar permisos.
- Proteger dashboards con MFA cuando el proveedor lo permita y no exponer paneles internos de producción públicamente.
- Añadir tests que fallen si aparecen propiedades prohibidas o URLs sin sanear.
- Revisar eventos y proveedores cada trimestre y eliminar los que no apoyen una decisión real.

Este documento no sustituye una revisión jurídica; define las garantías técnicas y las preguntas que esa revisión debe validar.

### 11. Distribución y atribución móvil

#### Beta con APK directa

- Medir `apk_download_clicked`, accesos NGINX al artefacto, registros y activaciones como series agregadas.
- Mostrar versión, SHA-256, fecha y pasos de instalación, trabajo que ya está en curso en la landing.
- No afirmar una relación individual campaña → instalación.
- Incluir opcionalmente tras el alta «¿Dónde conociste Better Calories?» con categorías cerradas y `prefiero no decirlo`.

#### Lanzamiento público recomendado

Mover Android a Google Play antes de invertir de forma significativa en adquisición. Reduce fricción y avisos de instalación, mejora confianza, actualizaciones y atribución mediante herramientas de la tienda. La cuenta de Play tiene actualmente una tasa única de 25 USD y las cuentas personales nuevas pueden tener requisitos de prueba.

Para iOS, TestFlight/App Store exige valorar la membresía anual de Apple Developer, publicada en 99 USD/año.

Cuando existan tiendas:

- añadir badges y eventos separados por store;
- usar Play Install Referrer y las capacidades de atribución permitidas por Apple;
- importar métricas agregadas de ficha, instalación, desinstalación y estabilidad;
- no mezclar identificadores publicitarios con datos nutricionales.

## Convención de campañas UTM

### Formato

| Campo | Regla | Ejemplos |
| --- | --- | --- |
| `utm_source` | plataforma o socio, minúsculas | `google`, `instagram`, `newsletter`, `coach_maria` |
| `utm_medium` | tipo de canal estable | `organic`, `social`, `creator`, `email`, `cpc`, `qr` |
| `utm_campaign` | objetivo + fecha o cohorte | `android_beta_2026q3` |
| `utm_content` | pieza o ubicación | `demo_voice_v1`, `bio_link`, `story_02` |
| `utm_term` | solo keyword de pago | `contador_calorias_voz` |

Reglas:

- minúsculas, ASCII, `snake_case` y sin datos personales;
- no inventar un nuevo nombre para el mismo canal;
- una URL final por pieza, guardada en un registro de campañas;
- validar enlaces antes de publicar;
- no usar acortadores de terceros si ocultan procedencia o añaden tracking;
- campañas sin UTM se clasifican como `direct/unknown`, no se corrigen a mano sin evidencia.

## Estrategia de marketing orientada a aprendizaje

### Orden recomendado

1. **Beta cualitativa:** 10–20 usuarios cercanos; observar alta/configuración, primera comida y fricción de la APK.
2. **Comunidades y creadores pequeños:** probar mensajes y audiencias con UTM individual, sin pagar o con acuerdos pequeños.
3. **SEO y contenido propio:** construir demanda acumulativa alrededor de casos reales del producto.
4. **Email propio:** convertir interés no preparado para instalar en una relación consentida.
5. **Pago limitado:** solo cuando registro → activación se mida y la tasa de activación sea estable.

### Experimentos iniciales

| Hipótesis | Canal | Pieza | KPI principal | Límite |
| --- | --- | --- | --- | --- |
| La voz reduce la fricción percibida | vídeo corto/comunidad | demo real de una comida | activados por 100 sesiones | 1 semana |
| La corrección genera confianza | creador/coach | propuesta antes/después | primera comida y corrección sana | 1 semana |
| Las comidas habituales aumentan retorno | email/contenido | flujo de reutilización | D7 de la cohorte | 2 semanas |
| La APK frena conversión | misma audiencia, antes/después de Play | CTA equivalente | descarga→registro | suficiente muestra |

Cada experimento tendrá:

- audiencia concreta;
- mensaje y cambio único;
- URL UTM;
- gasto y duración máximos;
- métrica primaria `usuarios activados`, no clics;
- guardrail de errores, coste y bajas;
- decisión `continuar`, `iterar` o `parar` con evidencia.

### Informe semanal de crecimiento

```text
1. Alcance e impresiones por canal
2. Sesiones y CTA por UTM
3. Descargas, registros y activados
4. D1/D7 de cohortes maduras
5. Principales abandonos y feedback cualitativo
6. Errores o incidentes que afectaron el embudo
7. Coste por activado y coste técnico por activado
8. Una decisión para la semana siguiente
```

## Fases y prioridades

### Fase 0 — Definición y línea base (1–2 días)

- Confirmar tipo de lanzamiento, territorios y presupuesto.
- Hacer un smoke de solo lectura en dev y producción: migraciones de telemetría aplicadas, admin habilitado, ingestión desde el build correspondiente, evento reciente consultable y worker de privacidad activo.
- Nombrar propietarios y canal de alertas.
- Aprobar métrica norte, activación y diccionario inicial.
- Crear registro de campañas y convención UTM.
- Completar mapa de datos/proveedores y criterio de consentimiento.
- Resolver email residual en `audit_events` y aprobar la retención/minimización de `action_calls` y argumentos de tools.
- Medir recursos, disco, logs y tamaño de backups actuales.

**Salida:** definiciones aprobadas y ningún evento ambiguo.

### Fase 1 — No lanzar a ciegas (3–5 días)

- Desplegar Umami en dev y producción con hardening y backup.
- Instrumentar páginas, CTA de descarga y eventos mínimos.
- Verificar Search Console y Bing; enviar sitemap.
- Desplegar Grafana OSS, Prometheus, Loki y Alloy con volúmenes, límites, retención y rotación local.
- Crear monitores sintéticos externos y alertas P1/P2.
- Configurar backup B2 con restic y realizar primera restauración.
- Verificar correlación de errores propios y logs por release/`traceId`; GlitchTip queda diferido.
- Actualizar privacidad y pruebas CSP.

**Salida:** visitas, descargas, caídas y excepciones visibles antes de abrir la beta.

### Fase 2 — Agregar la telemetría propia existente (3–5 días)

- Definir el hito de configuración inicial; no inventar un `onboarding_completed` sin comportamiento de producto que lo respalde.
- Crear vistas autoritativas de alta, primera comida, corrección, activación y cohortes D1/D7/D30 sobre datos ya persistidos.
- Añadir solo los eventos móviles ausentes: inicio de comida/voz, propuesta mostrada y abandono crítico.
- Incorporar `event_id`, `schema_version`, deduplicación y tests al canal cliente antes de usar esos eventos como KPI.
- Extender el panel admin con activación/retención y actualizar su documentación desfasada.
- Reconciliar una muestra manual extremo a extremo.
- Cruzar la vista de coste LLM ya implementada con comida y activado.

**Salida:** embudo y cohortes confiables sin duplicar la plataforma de telemetría.

### Fase 3 — Beta instrumentada (2–4 semanas)

- Incorporar 10–50 usuarios por cohortes controladas.
- Ejecutar 2–3 experimentos de canal, no todos a la vez.
- Revisar informe diario técnico y semanal de crecimiento.
- Corregir fricción antes de comprar tráfico.
- Establecer objetivos a partir de la línea base.

**Salida:** decisión fundada sobre lanzamiento público, mensaje y canales.

### Fase 4 — Lanzamiento público

- Publicar por Google Play; preparar iOS cuando el producto esté listo.
- Activar página/store listing, atribución y nuevos eventos.
- Ejecutar campaña con límites de gasto y rollback.
- Mantener seguimiento intensivo 48–72 horas.

### Fase 5 — Escala, solo si la evidencia lo pide

- Metabase para análisis SQL de negocio con rol read-only y vistas sin PII.
- OpenTelemetry/Tempo para trazas distribuidas si `traceId` y logs ya no bastan.
- Uptime Kuma y página de estado en segundo host.
- PostHog o plataforma de experimentación si hay volumen y equipo para gobernarla.
- Separar Umami/PostgreSQL de producción si el uso o aislamiento lo exige.
- CMP y píxeles de conversión únicamente con necesidad, consentimiento y revisión.

## Criterios de salida antes de abrir el lanzamiento

### Medición

- [ ] Una visita de prueba con UTM aparece en Umami con valores correctos.
- [ ] Un clic desde cada CTA relevante emite un único evento.
- [ ] El acceso NGINX a la APK permite contrastar el evento bloqueado por navegador.
- [ ] Alta real, configuración inicial acordada y primera comida aparecen en el panel propio.
- [ ] Duplicar/reintentar una petición no duplica la conversión autoritativa.
- [ ] Una cohorte de prueba produce D1/D7 reproducibles.
- [ ] Un recorrido manual se reconcilia entre Umami, backend y panel sin pretender unir lo que la APK no permite.

### Fiabilidad

- [ ] Landing, API, manifiesto APK y TLS se monitorizan desde fuera del VPS durante al menos siete días.
- [ ] Una alerta simulada llega a la persona responsable por dos canales.
- [ ] Grafana muestra CPU, RAM, disco, contenedores, NGINX, backend y PostgreSQL.
- [ ] Los logs tienen release y `traceId`, y no contienen secretos o cuerpos sensibles.
- [ ] Un error controlado de Flutter y backend puede localizarse por release/`traceId` entre telemetría propia y Loki.
- [ ] Hay rotación local de logs y alerta de disco.
- [ ] El dashboard muestra el digest/release desplegado.

### Recuperación y despliegue

- [ ] El backup diario llega cifrado a B2.
- [ ] Se ha restaurado desde B2 en un entorno aislado.
- [ ] Se han medido RPO/RTO y documentado la última prueba.
- [ ] El procedimiento blue/green, smoke y rollback sigue funcionando con los nuevos servicios.
- [ ] Umami puede actualizarse o revertirse sin afectar la API.

### Privacidad y seguridad

- [ ] La política publicada describe analítica, observabilidad, errores, email y backups.
- [ ] Existe inventario de proveedores, región, DPA y conservación.
- [ ] Umami no usa Distinct ID, PII, replay ni parámetros de URL no permitidos.
- [ ] Prometheus y Loki reciben únicamente métricas/logs revisados y saneados.
- [ ] `audit_events` no conserva email tras el alta o la eliminación de cuenta; `action_calls` tiene retención/minimización aprobada.
- [ ] La decisión sobre consentimiento está documentada.
- [ ] Dashboards locales solo son accesibles por túnel SSH y conservan login propio; buckets y servicios externos tienen acceso mínimo, MFA y credenciales separadas.

### Crecimiento

- [ ] Todas las piezas del lanzamiento usan la convención UTM.
- [ ] Existe una hoja de campañas con gasto, alcance, clics, sesiones, activados y decisión.
- [ ] Hay un canal de feedback y respuesta a incidencias.
- [ ] Se ha decidido APK privada frente a Google Play público.
- [ ] No se compra tráfico hasta verificar el embudo de activación.

## Runbook de lanzamiento

### Siete días antes

- Congelar taxonomía de eventos y dashboards.
- Ejecutar restore test, smoke de despliegue y prueba sintética de navegador.
- Confirmar cuota y facturación de proveedores.
- Revisar política, tienda/descarga, soporte y mensajes.
- Ejecutar un ensayo con campaña UTM de prueba.

### Un día antes

- Comprobar backup, disco, certificados, DNS y estado de proveedores.
- Verificar versión/digest y anotación de release en Grafana.
- Preparar rollback y mensaje de estado.
- Evitar cambios no relacionados.

### Primera hora

- Publicar una única cohorte pequeña.
- Comprobar landing, descarga, registro, primera comida y alertas.
- Contrastar Umami, NGINX, backend, Grafana y la telemetría propia.

### Primeras 72 horas

- Revisar P1/P2, 5xx, crashes y capacidad varias veces al día.
- Separar fallos técnicos de abandono de producto.
- Pausar campañas si el flujo crítico está degradado.
- Publicar correcciones pequeñas con anotación y verificar regresión.

### Después

- Pasar a revisión técnica diaria de 15 minutos.
- Hacer revisión semanal de crecimiento/producto.
- Revisar mensualmente restauración, retención, accesos, costes y herramientas sin uso.

## Presupuesto estimado

Precios consultados el 22 de julio de 2026; deben reconfirmarse antes de contratar.

| Elemento | Opción inicial | Coste de referencia |
| --- | --- | ---: |
| Umami | autohospedado en VPS actual | 0 € marginal + operación |
| Umami Cloud | Hobby | 0 €, sujeto a límites vigentes |
| Grafana/Prometheus/Loki/Alloy | autohospedados en VPS actual | 0 € marginal + CPU, RAM, disco y operación |
| UptimeRobot | Free | 0 €; checks cada 5 minutos, sujeto a límites vigentes |
| GlitchTip | diferido | 0 € durante la beta |
| Backblaze B2 | primeras copias | primeros 10 GB gratis; después 6,95 USD/TB/mes |
| listmonk | autohospedado | 0 € marginal + operación |
| Amazon SES Essentials | email | 0,16 USD/1.000 emails + datos, según tarifa actual |
| Search Console/Bing | SEO | 0 € |
| Google Play Console | distribución Android | 25 USD, pago único |
| Apple Developer Program | distribución iOS | 99 USD/año |
| Uptime Kuma alternativo | segundo VPS | software 0 € + alojamiento del proveedor |

### Escenarios

| Escenario | Recurrente aproximado | Comentario |
| --- | ---: | --- |
| Beta mínima elegida | 0 €/mes | Umami y pila Grafana en el VPS; monitor externo gratuito; B2 dentro de cuota |
| Más capacidad | coste del proveedor VPS | ampliar disco/RAM si la medición demuestra falta de margen |
| Aislamiento extra futuro | ~20–30 €/mes | segundo VPS pequeño o servicio gestionado si la operación local deja de compensar |

No se debe elegir autohospedado solo porque la licencia sea gratuita. Si mantener una herramienta consume más horas que su plan alojado, el SaaS barato puede ser la opción económicamente correcta.

## Criterios de aceptación

- El equipo puede responder en menos de diez minutos cuántas sesiones, descargas, altas y activados produjo una campaña.
- Las definiciones de todos esos números están versionadas y sus fuentes identificadas.
- Se puede distinguir entre falta de tráfico, abandono de producto y degradación técnica.
- Los eventos de conversión críticos proceden de una fuente autoritativa y son idempotentes.
- Ningún proveedor externo recibe email, texto libre, nutrición, audio o transcripciones.
- Una caída de producción genera una alerta externa dentro del objetivo de diez minutos.
- Una excepción nueva puede localizarse por release y correlacionarse con logs mediante `traceId`.
- El servicio puede restaurarse desde una copia externa dentro del RTO acordado.
- La campaña UTM de prueba recorre el embudo disponible sin fingerprinting.
- El coste mensual y las cuotas se muestran y alertan antes de producir pérdida silenciosa de datos.
- La política de privacidad y el inventario de proveedores reflejan la configuración desplegada.

## Validación de la auditoría actual

La revisión se realizó contra el código actual de `develop`, no solo contra las especificaciones históricas. Se validaron específicamente:

- **Backend:** 26 pruebas de `adminTelemetry.test.ts` y `telemetry.test.ts`; cubren auth del panel, overview, filtros, trace completo, ingestión móvil, límites de contrato, saneamiento, redacción, STT, LLM, búsqueda y comportamiento best-effort. Resultado: **26/26 correctas**.
- **Flutter:** `client_telemetry_service_test.dart`, `api_client_telemetry_test.dart`, `nutrition_repository_telemetry_test.dart` y `voice_log_telemetry_test.dart`. Resultado: **21/21 correctas**.
- **Panel admin:** validación estática completa y pruebas de la política de orígenes/autorización correctas; se confirmaron las once vistas efectivas y los endpoints consumidos. Su README solo enumera la primera versión y debe actualizarse.

Estas pruebas confirman que la base propia funciona. No validan que las migraciones estén aplicadas ni que el panel/credenciales estén habilitados en el VPS de producción; eso requiere un smoke no mutante del entorno desplegado antes del lanzamiento.

## Impacto previsto en el proyecto

Las áreas probablemente afectadas durante una implementación posterior son:

- `apps/landing`: tracker, eventos, saneamiento UTM, CSP, privacidad y tests.
- `apps/mobile`: pocos eventos de interacción ausentes, idempotencia/persistencia proporcional al riesgo, release/`traceId` y redacción.
- `apps/backend`: deduplicación del canal cliente, vistas autoritativas, métricas Prometheus/OpenTelemetry, logs estructurados y agregaciones; no una nueva plataforma de eventos.
- `apps/admin`: paneles agregados de alta, activación y retención; la vista de coste ya existe y debe ampliarse, no rehacerse.
- `infra/deploy`: Umami, Grafana, Prometheus, Loki, Alloy/exporters, límites, healthchecks, volúmenes, backup externo y secretos.
- `infra/deploy/nginx`: subdominio de analítica, rutas, TLS, access logs y CSP.
- `.github/workflows`: anotaciones de release, validación y smoke.
- `docs`: política, inventario de datos, runbooks, SLO, alertas, eventos y campañas.

La implementación debe dividirse en fichas o PR independientes para web analytics, observabilidad local, backups y agregaciones de producto sobre la telemetría existente. Crash reporting externo queda fuera de la primera implementación. Este documento conserva la visión conjunta y el orden.

## Decisiones confirmadas

- Priorizar herramientas open source, gratuitas o muy baratas.
- Incluir Umami como candidato principal para la landing.
- Incluir Grafana solo donde aporte observabilidad operativa, no como sustituto de analítica de marketing.
- Alojar Umami, Grafana OSS, Prometheus, Loki y Alloy en el VPS actual para minimizar cuentas y operación distribuida.
- No añadir VPN durante la beta; los paneles internos se enlazarán a loopback/red Docker y se accederá mediante túnel SSH con clave.
- Usar Grafana Alerting en lugar de desplegar Alertmanager.
- Aceptar que la pila local no detecta la caída total del VPS y mantener como única excepción un monitor HTTP externo gratuito.
- Mantener los backups cifrados fuera del VPS; una copia exclusivamente local no se considera recuperación ante desastre.
- Mantener PostgreSQL y el panel admin propios como fuente de analítica del producto autenticado; no introducir PostHog en el lanzamiento.
- Diferir GlitchTip; reconsiderarlo solo si la telemetría propia y Loki no permiten diagnosticar crashes reales.
- Crear un plan Markdown dentro del repositorio sin implementar todavía la infraestructura.

## Supuestos

- El primer lanzamiento será una beta Android para España/UE.
- La APK directa seguirá siendo el canal inicial, pero Google Play se evaluará antes de promoción pública con gasto.
- El tráfico inicial cabrá en los niveles gratuitos.
- El presupuesto recurrente aceptable está entre 0 y 20 € al mes.
- Un equipo pequeño o una sola persona operará el sistema.
- Se prefiere minimizar PII y evitar consentimiento cuando una configuración de medición estrictamente necesaria y validada lo permita.

## Preguntas abiertas

1. ¿El siguiente hito es una beta privada/abierta por APK en España/UE o un lanzamiento público en Google Play y más territorios?
2. ¿Qué hecho debe representar «configuración inicial completada»: objetivo calórico configurado, macros configurados u otro comportamiento?
3. ¿Cuánto disco total y libre tiene ahora el VPS? Es el dato que falta para confirmar la retención de 7 días de logs y 15 días de métricas sin poner PostgreSQL en riesgo.

## Fuentes externas

- [Umami: introducción, privacidad y capacidades](https://docs.umami.is/docs)
- [Umami: instalación con Docker y PostgreSQL](https://docs.umami.is/docs/install)
- [Umami: rutas del tracker y del collector](https://docs.umami.is/docs/bypass-ad-blockers)
- [Umami: eventos personalizados](https://docs.umami.is/docs/track-events)
- [Umami: campañas UTM](https://docs.umami.is/docs/utm)
- [Umami: configuración del tracker y Do Not Track](https://docs.umami.is/docs/tracker-configuration)
- [Umami: definición de sesiones y uso de IP](https://docs.umami.is/docs/metric-definitions)
- [Grafana Cloud: precios y límites gratuitos](https://grafana.com/pricing/)
- [Grafana Alloy: recogida y reenvío de métricas, logs y OpenTelemetry](https://grafana.com/docs/alloy/latest/collect/)
- [Grafana Alloy: acceso, permisos, loopback y TLS](https://grafana.com/docs/alloy/latest/access_permissions/)
- [Grafana Alloy: componentes para métricas y logs](https://grafana.com/docs/alloy/latest/collect/choose-component/)
- [Grafana: ejecución en Docker y almacenamiento persistente](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Grafana Alerting: puntos de contacto](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/contact-points/)
- [Prometheus: almacenamiento y retención local](https://prometheus.io/docs/prometheus/latest/storage/)
- [Grafana Loki: instalación monolítica con Docker/Compose](https://grafana.com/docs/loki/latest/setup/install/docker/)
- [Grafana Loki: límites del almacenamiento local en filesystem](https://grafana.com/docs/loki/latest/operations/storage/filesystem/)
- [GlitchTip: SDK Flutter](https://glitchtip.com/sdkdocs/dart-flutter/)
- [GlitchTip: precios alojados](https://beta.glitchtip.com/pricing/)
- [GlitchTip: autenticación multifactor TOTP](https://glitchtip.com/blog/2021-09-17-glitchtip-1-8/)
- [WireGuard: configuración y pares con claves](https://www.wireguard.com/quickstart/)
- [Let's Encrypt: certificados automatizados con ACME](https://letsencrypt.org/getting-started/)
- [Uptime Kuma: repositorio y capacidades](https://github.com/louislam/uptime-kuma)
- [UptimeRobot: plan gratuito y límites](https://uptimerobot.com/pricing/)
- [Backblaze B2: precios](https://www.backblaze.com/cloud-storage/pricing)
- [restic: copias cifradas y verificables](https://restic.net/)
- [listmonk: documentación y licencia](https://listmonk.app/docs/)
- [Amazon SES: precios](https://aws.amazon.com/ses/pricing/)
- [Google Search Console](https://search.google.com/search-console/about)
- [Bing Webmaster Tools](https://www.bing.com/webmasters/about)
- [AEPD: uso de herramientas de medición de audiencia](https://www.aepd.es/guias/guia-cookies-analiticas-externas.pdf)
- [AEPD: guía sobre el uso de cookies](https://www.aepd.es/es/documento/guia-cookies.pdf)
- [Klaro: gestor de consentimiento open source](https://github.com/kiprotect/klaro)
- [Google Play Console: registro y tasa](https://support.google.com/googleplay/android-developer/answer/6112435)
- [Google Play: Install Referrer](https://developer.android.com/google/play/installreferrer)
- [Apple Developer Program: membresía](https://developer.apple.com/programs/whats-included/)
- [Apple: AdAttributionKit](https://developer.apple.com/app-store/ad-attribution/)
