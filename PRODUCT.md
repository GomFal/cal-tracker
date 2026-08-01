---
title: Better Calories — Documento central de producto
version: 1.0
status: snapshot del producto y marco de decisión
date_created: 2026-07-16
last_updated: 2026-07-16
baseline_commit: 2d03ae6
owner: Equipo Better Calories
audience:
  - fundadores
  - producto
  - ingeniería
  - diseño
  - marketing
  - operaciones
tags:
  - producto
  - estrategia
  - negocio
  - nutrición
  - inteligencia-artificial
---

# Better Calories

## 1. Propósito de este documento

Este archivo centraliza qué es Better Calories, qué problema intenta resolver, qué ofrece hoy, cómo funciona, a quién se dirige, qué riesgos tiene y qué decisiones empresariales siguen abiertas.

Debe servir para:

- alinear al equipo sobre la realidad actual del producto;
- evitar confundir visión, prototipo, código existente y promesas comerciales;
- evaluar prioridades de producto, distribución, monetización y operaciones;
- identificar riesgos que deben resolverse antes de ampliar la beta;
- definir métricas comunes para comprobar si existe valor y retención;
- mantener un punto de entrada para nuevas personas del equipo.

No sustituye las especificaciones técnicas detalladas. Resume y traduce el repositorio a una visión de producto y negocio.

Para comportamiento técnico, prevalecen, por este orden:

1. observación fechada del entorno realmente desplegado;
2. código ejecutable, contratos, migraciones y tests del commit desplegado;
3. decisiones formales y documentación técnica propietaria del dominio;
4. este documento;
5. landing, copy comercial y planes históricos.

Para obligaciones legales, comerciales o societarias prevalecen los contratos, políticas vigentes, decisiones formales y asesoramiento profesional aplicable; el código no reemplaza esas fuentes.

### 1.1 Cómo leer los estados

| Estado | Significado |
| --- | --- |
| **Implementado** | Hay una ruta verificable en el producto o backend actual. |
| **Parcial** | Existe una parte útil, pero falta exposición, cierre operativo o consistencia. |
| **Experimental** | Está construido o preparado, pero no debe tratarse como promesa estable. |
| **Planificado** | Está descrito en documentación, pero no forma parte comprobable del producto actual. |
| **No implementado** | No existe una solución observable en el baseline revisado. |
| **Desconocido** | El repositorio no contiene información suficiente para afirmarlo. |

Las secciones de estrategia distinguen además entre:

- **Hecho**: verificable en el repositorio o en una decisión ya documentada.
- **Inferencia**: lectura razonable de las señales existentes, pendiente de validación con usuarios o mercado.
- **Recomendación**: propuesta para discusión; no es una decisión tomada.

---

## 2. Resumen ejecutivo

Better Calories es una aplicación móvil de seguimiento nutricional que busca que registrar una comida sea tan natural como contar lo que se ha comido. El usuario puede escribir, hablar, buscar alimentos o reutilizar comidas habituales; el recorrido normal transforma esa entrada en datos estructurados de calorías y macronutrientes, muestra una propuesta revisable y solicita confirmación antes de guardar. La garantía general de confirmación server-side todavía es incompleta.

La tesis del producto es:

> Las personas pueden registrar comidas recurrentes con menos esfuerzo y suficiente confianza si combinamos lenguaje natural, voz, memoria personal, datos nutricionales trazables y una revisión estructurada antes de guardar.

El producto no pretende ser un chatbot nutricional genérico ni una base de datos manual con IA decorativa. Su diferenciación potencial está en la unión de cinco elementos:

1. registro mediante lenguaje natural y voz;
2. propuestas estructuradas que se pueden inspeccionar y corregir;
3. datos nutricionales de fuentes conocidas y alimentos aportados por el usuario;
4. reutilización de ingredientes, alias y comidas frecuentes;
5. una capa de acciones segura que separa la interpretación de la escritura real en el historial.

### 2.1 Situación actual

- El núcleo funcional es un MVP avanzado y utilizable, no solo una maqueta.
- La distribución pública está orientada a una beta Android mediante APK directa.
- La app móvil está en versión de código `0.1.9+21` en el baseline revisado.
- Existen entornos backend de desarrollo y producción, despliegue blue/green, PostgreSQL, landing, descarga y panel administrativo.
- El registro manual, la voz, el agente, las propuestas, el historial, los objetivos, la hidratación, los alimentos habituales, las plantillas y el OCR de etiquetas tienen implementación real.
- La telemetría técnica y de coste de IA es considerablemente más madura que la analítica de activación, retención y conversión.
- No existe monetización, sistema de suscripciones, paywall ni entitlement observable.
- La privacidad, el consentimiento, la retención, la exportación y el borrado integral de cuenta no están cerrados para una distribución amplia.
- iOS es un objetivo arquitectónico, pero no una superficie comercial cerrada en el baseline.
- La memoria vectorial, la búsqueda semántica y el modo de autoconfirmación existen como arquitectura parcial; no deben venderse como capacidades plenamente activas.

### 2.2 Conclusión empresarial

Better Calories ya tiene suficiente producto para medir si su propuesta reduce la fricción del registro. Aún no tiene suficiente infraestructura empresarial para escalar adquisición o cobrar con confianza.

La siguiente etapa no debería consistir únicamente en añadir funciones. Debería cerrar cuatro frentes:

1. **seguridad y confianza empresarial**: privacidad, consentimiento, retención, exportación, borrado, backups, firma y abuso;
2. **enfoque**: decidir cuál es el recorrido principal entre agente, creación manual, voz y habituales;
3. **evidencia**: instrumentar activación, tiempo de registro, confirmación, corrección, recurrencia y retención;
4. **modelo comercial**: conocer el coste por comida confirmada y por usuario activo antes de fijar planes y límites.

---

## 3. Definición del producto

### 3.1 Definición en una frase

Better Calories es un diario nutricional móvil que convierte texto, voz, búsquedas y comidas habituales en registros revisables de calorías, macros y agua.

### 3.2 Promesa al usuario

> Registra comidas como hablas, revisa antes de guardar y reutiliza lo que comes habitualmente.

### 3.3 Problema principal

Los diarios nutricionales tradicionales imponen una carga repetitiva:

- buscar cada alimento;
- elegir entre resultados similares;
- introducir porciones y unidades;
- repetir comidas ya registradas;
- corregir valores poco claros;
- mantener objetivos y consultar el progreso en pantallas separadas.

La hipótesis es que esta carga reduce la adherencia; debe validarse con cohortes, observación y entrevistas. El producto parte además de que muchas comidas reales son recurrentes, se describen de forma incompleta y ocurren en momentos en los que el usuario no quiere realizar trabajo administrativo.

### 3.4 Solución propuesta

Better Calories combina:

- entrada por texto, voz, búsqueda manual y plantillas;
- interpretación estructurada por un agente backend;
- resolución contra datos nutricionales y alimentos del usuario;
- propuesta previa al commit;
- corrección de ingredientes, cantidades y macros;
- historial y resumen diario;
- memoria de comidas habituales y alias;
- trazabilidad técnica de acciones, búsquedas, transcripciones y costes.

### 3.5 Trabajo que el usuario contrata

El trabajo funcional principal es:

> “Cuando termino de comer o quiero planificar mi día, ayúdame a registrar lo que he comido con el mínimo esfuerzo, sin hacerme perder el control sobre los datos.”

Trabajos complementarios:

- saber cuántas calorías y macros quedan hoy;
- revisar qué se comió en un día reciente;
- corregir o eliminar una comida;
- configurar un objetivo calórico y de macronutrientes;
- llevar el consumo de agua;
- reutilizar una comida o ingrediente frecuente;
- convertir una etiqueta nutricional en un alimento personal;
- preguntar al agente por el estado del día o pedirle una acción nutricional.

### 3.6 Resultado deseado

El producto tiene éxito para el usuario cuando:

- puede registrar una comida frecuente en segundos;
- entiende qué se va a guardar;
- puede corregir errores sin rehacer el flujo;
- confía en la procedencia de los valores;
- vuelve a registrar durante varias semanas;
- percibe que el producto aprende sus hábitos sin actuar fuera de su control.

---

## 4. Usuarios, segmentos y límites

### 4.1 Usuario principal actual

La evidencia del producto y la landing apunta a personas adultas que hacen seguimiento nutricional individual, especialmente:

- usuarios que controlan calorías y macros;
- personas con objetivo de pérdida, mantenimiento o ganancia de peso;
- usuarios de gimnasio o entrenamiento con comidas repetitivas;
- personas que cocinan en casa y repiten recetas;
- consumidores de productos envasados de supermercado;
- usuarios que valoran la voz o el lenguaje natural para ahorrar tiempo;
- usuarios de España y la Unión Europea, con unidades métricas, español y productos regionales.

### 4.2 Segmento inicial recomendado

**Recomendación**: enfocar la beta en un ICP estrecho:

> Persona adulta en España o la UE que ya intenta controlar calorías o macros, repite una parte relevante de sus comidas y abandona o evita los diarios tradicionales por la fricción de registrar.

Este segmento encaja con lo ya construido y permite probar la tesis de recurrencia sin abrir todavía un frente clínico o profesional.

### 4.3 Segmentos secundarios posibles

Son extensiones plausibles, no mercados validados:

- personas que solo necesitan conciencia alimentaria, no precisión de culturismo;
- usuarios con recetas familiares repetidas;
- deportistas recreativos;
- personas que quieren digitalizar alimentos propios mediante etiquetas;
- usuarios bilingües español/inglés.

### 4.4 No es hoy un producto para

- diagnóstico, tratamiento o seguimiento médico;
- dietas prescritas para patologías;
- menores de edad;
- nutricionistas con cartera de pacientes;
- familias o cuentas compartidas;
- restauración, inventario o planificación de menús empresariales;
- análisis clínico de micronutrientes;
- wearables o seguimiento deportivo avanzado;
- web o escritorio como experiencia principal.

### 4.5 Supuestos de usuario pendientes de validar

- Las comidas repetitivas representan suficiente volumen como para crear un hábito de uso.
- La voz reduce el tiempo total incluso contando revisión y corrección.
- Los usuarios prefieren una propuesta revisable frente a un registro inmediato opaco.
- La trazabilidad de fuentes influye en la confianza y retención.
- El usuario está dispuesto a crear habituales para obtener velocidad futura.
- El agente aporta más valor que una interfaz manual optimizada en todos los segmentos.

---

## 5. Posicionamiento y marca

### 5.1 Posicionamiento actual

La landing presenta Better Calories como una app móvil de nutrición diaria para contar calorías y macros sin convertir cada comida en una tarea. El mensaje combina velocidad y control:

- “habla o escribe”;
- “revisa la propuesta”;
- “corrige porciones”;
- “guarda solo cuando todo encaja”.

### 5.2 Diferenciadores potenciales

| Diferenciador | Valor para el usuario | Estado |
| --- | --- | --- |
| Lenguaje natural y voz | Reduce tecleo y búsqueda manual. | Implementado. |
| Propuesta antes de guardar | Aumenta control y permite corregir. | Implementado. |
| Comidas e ingredientes habituales | Convierte repetición en velocidad. | Implementado, con flujos aún fragmentados. |
| Procedencia nutricional | Reduce dependencia de valores inventados. | Implementado de forma relevante. |
| Acción canónica segura | La IA interpreta, pero no escribe directamente en la base de datos. | Implementada arquitectónicamente; confirmación e idempotencia aún tienen garantías incompletas. |
| OCR de etiqueta | Acelera la creación de alimentos propios. | Implementado en Android/móvil compatible. |
| Memoria personal semántica | Podría reconocer hábitos y frases variables. | Parcial; no vender como plenamente activa. |
| Coste LLM observable | Aporta una base para estimar costes variables y diseñar unit economics. | Implementado en gran parte para LLM; STT, infraestructura y soporte requieren cálculo adicional. |

### 5.3 Personalidad de marca

La marca debe sentirse:

- fresca;
- fiable;
- ligera;
- directa;
- calmada;
- práctica.

La comunicación no debe ser agresiva, culpabilizadora ni clínica. El producto debe ayudar a registrar, no convertir la alimentación en una competición permanente.

### 5.4 Antirreferencias

Better Calories no debe parecer:

- un buscador de base de datos donde el usuario hace todo el trabajo;
- una app médica o de cumplimiento clínico;
- un panel de gimnasio oscuro y saturado de métricas agresivas;
- un chatbot que oculta acciones estructuradas;
- una hoja de cálculo de macros;
- una aplicación genérica de IA que inventa nutrición;
- una experiencia que premia la obsesión o castiga visualmente un día imperfecto.

### 5.5 Deuda de identidad

El repositorio usa `Cal Tracker`, `BetterCalories` y `Better Calories` en diferentes superficies. La marca pública principal es Better Calories, mientras algunos identificadores, nombres internos y configuraciones mantienen el nombre anterior.

**Decisión pendiente**: fijar una guía de naming para nombre comercial, nombre de app, identificadores técnicos, repositorio y copy.

---

## 6. Principios de producto

1. **Velocidad sin adivinación.** Registrar debe ser rápido, pero los datos propuestos deben seguir siendo inspeccionables.
2. **Confianza antes que automatización.** Confirmación, corrección, procedencia y auditoría son parte del valor.
3. **La repetición debe volverse barata.** Cada comida habitual confirmada debería reducir el esfuerzo futuro.
4. **La IA interpreta; las acciones deterministas escriben.** El modelo no debe mutar datos directamente.
5. **PostgreSQL es la fuente de verdad.** Los embeddings y la memoria semántica ayudan a recuperar, no sustituyen los registros estructurados.
6. **No inventar nutrición.** Los valores deben proceder de bases conocidas, alimentos del usuario, plantillas confirmadas o entrada explícita.
7. **Mostrar los números útiles de forma clara.** Calorías, macros, porciones, fechas y etiquetas deben poder escanearse.
8. **Una pantalla, un trabajo principal.** Registrar, confirmar, corregir, revisar o ajustar deben tener prioridades visuales distintas.
9. **La voz complementa.** Toda acción central debe seguir siendo posible con texto o controles táctiles.
10. **El producto no hace afirmaciones médicas.** Las estimaciones son orientativas y el sistema no diagnostica ni prescribe.

---

## 7. Estado y madurez del producto

### 7.1 Etapa

**Inferencia**: beta privada o controlada con un MVP funcional avanzado.

La conclusión se apoya en:

- versión móvil anterior a 1.0;
- descarga directa de APK;
- documentación de prioridades de “private beta”;
- panel de inspección de conversaciones y costes;
- ausencia de monetización, legal público completo y distribución en stores;
- presencia de gaps de seguridad, cuenta y operación reconocidos por la propia arquitectura.

### 7.2 Superficies existentes

| Superficie | Propósito | Estado |
| --- | --- | --- |
| App Flutter | Experiencia principal de usuario. | Implementado; beta Android, iOS incompleto. |
| Backend Bun/TypeScript | Auth, acciones, agente, STT, nutrición y API. | Implementado. |
| PostgreSQL + pgvector | Fuente de verdad y soporte vectorial. | Implementado; vectorial parcial en runtime. |
| Landing | Propuesta de valor, SEO y acceso a descarga. | Implementado. |
| Página de descarga | Entrega de última APK Android. | Implementado. |
| Panel admin | Telemetría, trazas, costes, conversaciones y fallos. | Implementado para entorno administrativo. |
| Importadores USDA/OFF | Alimentación del corpus nutricional. | Implementado como tooling. |
| Integraciones App Store/Play Store | Distribución oficial. | No implementado. |
| Android AppFunctions/iOS App Intents | Acciones desde agentes del sistema operativo. | Planificado/experimental fuera del núcleo actual. |

### 7.3 Capacidades por estado

| Área | Capacidad | Estado actual |
| --- | --- | --- |
| Cuenta | Registro e inicio email/contraseña | Implementado. |
| Cuenta | Inicio con Google | Implementado en Android; configuración iOS no cerrada. |
| Cuenta | Refresh, logout y revocación de sesiones backend | Parcial: revoca refresh sessions; el access JWT emitido sigue válido hasta su TTL de 15 minutos. |
| Cuenta | Recuperación de contraseña completa en móvil | Parcial: API sin recorrido móvil/delivery productivo cerrado y sin revocación de sesiones existentes tras reset. |
| Cuenta | Verificación de email | No implementado en el baseline. |
| Cuenta | Exportación y eliminación integral | No implementado. |
| Objetivos | Calorías manuales | Implementado. |
| Objetivos | Calculadora orientativa | Implementado. |
| Objetivos | Macros por presets, porcentajes o gramos | Implementado. |
| Hidratación | Objetivo y consumo diario | Implementado. |
| Diario | Resumen diario | Implementado. |
| Diario | Historial y edición/eliminación | Implementado. |
| Diario | Tendencias largas, peso o adherencia | No implementado. |
| Registro | Búsqueda manual de alimentos | Implementado. |
| Registro | Texto a propuesta | Implementado. |
| Registro | Voz a transcripción y propuesta | Implementado. |
| Registro | Clarificación de candidatos | Implementado. |
| Registro | Revisión, edición y commit | Implementado. |
| Habituales | CRUD de ingredientes personales | Implementado. |
| Habituales | CRUD de comidas y alias | Implementado. |
| Habituales | OCR de etiqueta | Implementado. |
| Habituales | Escáner de código de barras | No expuesto como lector; solo existe soporte de campo/búsqueda. |
| Agente | Chat texto y audio | Implementado. |
| Agente | Historial de conversaciones | Implementado; borrar significa ocultar, no eliminar físicamente. |
| Agente | Herramientas nutricionales | Implementado. |
| Agente | Memoria vectorial completa | Parcial. |
| Automatización | Trusted auto-commit | No operativo como función de usuario en el baseline. |
| Idiomas | Inglés y español | Implementado con cadenas residuales no localizadas. |
| Tema | Claro, oscuro y sistema | Implementado. |
| Offline | Caché y stale-while-revalidate | Implementado para datos visibles. |
| Offline | Uso completo sin red y cola de sincronización | No implementado. |
| Monetización | Suscripciones/pagos/planes | No implementado. |

---

## 8. Experiencia de usuario actual

### 8.1 Acceso

La app abre en autenticación cuando no hay sesión válida. Permite:

- crear cuenta con nombre, email y contraseña;
- iniciar sesión con email y contraseña;
- continuar con Google;
- restaurar sesiones mediante tokens en almacenamiento seguro.

Brechas actuales:

- el formulario mantiene credenciales de demostración precargadas;
- no hay recuperación de contraseña visible;
- no hay verificación de email visible;
- no hay aceptación de términos o privacidad;
- no hay edición de perfil ni eliminación de cuenta;
- un error de red durante la restauración puede limpiar tokens y bloquear el acceso cacheado tras un arranque en frío.

Riesgo crítico de linking: una cuenta local puede registrarse con un email no verificado y, después, el login de Google para ese mismo email se enlaza automáticamente al usuario existente. Un atacante podría prerregistrar el email de otra persona y conservar acceso por contraseña cuando la víctima use Google. Antes de ampliar la beta debe verificarse el email local y requerirse reautenticación o consentimiento explícito para enlazar proveedores, o rechazarse el conflicto.

### 8.2 Onboarding

No existe un onboarding separado y completo. Tras autenticarse, el usuario entra al dashboard. La configuración calórica aparece cuando el usuario la solicita o cuando el producto detecta que aún no está configurada.

La calculadora pregunta por:

- sexo biológico;
- edad;
- altura;
- peso;
- nivel de actividad;
- objetivo de pérdida, mantenimiento o ganancia;
- ritmo deseado cuando aplica.

Los datos se usan para estimar calorías, pero no forman un perfil persistente editable.

**Riesgo de producto**: el usuario puede llegar al dashboard sin comprender el valor diferencial ni completar el momento de activación.

### 8.3 Navegación

La experiencia móvil se organiza alrededor de:

- **Inicio**: resumen diario y comidas;
- **Estadísticas**: semana e historial;
- **Agente**: acción central para texto o voz;
- **Mis alimentos**: comidas e ingredientes habituales;
- **Menú**: cuenta, objetivos y preferencias.

En pantallas anchas cambia a navegación lateral y mantiene el estado de las ramas.

### 8.4 Dashboard

El dashboard muestra:

- saludo y fecha;
- calorías consumidas, objetivo y restantes;
- progreso de proteína, carbohidratos y grasa;
- consumo y objetivo de agua;
- comidas del día;
- acciones para crear, editar o eliminar;
- entrada a configuración de objetivos.

Los cambios deterministas aplican actualización optimista y rollback ante rechazo del backend.

### 8.5 Registro manual

La creación de comida permite:

1. buscar alimentos;
2. seleccionar resultados;
3. ajustar cantidad, unidad y nutrición;
4. combinar ingredientes;
5. revisar una propuesta;
6. editar o confirmar;
7. asignar una etiqueta o título de comida.

Esta superficie conserva parte de la implementación histórica de voz y contiene cadenas visibles en inglés aunque el locale sea español.

### 8.6 Registro por agente y voz

El botón central abre el agente. Una pulsación prolongada puede comenzar grabación directa y enviar el audio al soltar.

El agente permite:

- mensajes por texto;
- grabación y transcripción;
- respuestas progresivas;
- uso de herramientas estructuradas;
- consulta del resumen, objetivos restantes e historial;
- búsqueda de nutrición;
- propuesta, revisión y registro de comidas;
- creación de borradores revisables de alimentos o comidas habituales;
- selección de candidatos ambiguos;
- historial de conversaciones.

Flujo ideal:

```text
entrada del usuario
  -> transcripción si hay audio
  -> interpretación del agente
  -> búsqueda/memoria/herramienta
  -> propuesta o aclaración
  -> revisión/corrección
  -> acción determinista
  -> historial y resumen actualizados
```

### 8.7 Historial y estadísticas

La pantalla actual ofrece:

- gráfico semanal de calorías;
- selección de día dentro de la semana;
- comidas del día seleccionado;
- edición y eliminación;
- estados de carga, vacío y error.

No ofrece todavía:

- navegación histórica amplia;
- tendencias mensuales o anuales;
- evolución de peso;
- adherencia a objetivos;
- correlaciones o recomendaciones longitudinales.

### 8.8 Habituales

El usuario puede crear y mantener:

- ingredientes personales;
- comidas reutilizables;
- alias de lenguaje natural;
- porciones y macros;
- código de barras como dato;
- nutrientes opcionales de etiqueta.

Las plantillas se pueden registrar rápidamente en el diario. Los borradores asistidos existen, pero su acceso no está completamente integrado en todas las entradas de “Habituales”.

### 8.9 Escaneo de etiquetas

El flujo de escaneo:

1. solicita permiso de cámara;
2. captura la etiqueta;
3. permite revisar o repetir;
4. recorta la región nutricional;
5. ejecuta OCR latino en el dispositivo;
6. envía el texto al backend para crear un borrador estructurado;
7. exige revisión antes de guardar.

La foto no se interpreta nutricionalmente solo en el dispositivo: el OCR es local, pero la estructuración depende del backend y del proveedor LLM.

### 8.10 Ajustes

La app expone:

- nombre y email de solo lectura;
- objetivo de hidratación;
- objetivo calórico;
- distribución de macros;
- idioma;
- tema;
- atribución de fuentes de datos;
- cierre de sesión;
- herramientas de rendimiento en builds no release.

No expone de forma completa:

- perfil editable;
- trusted mode;
- dispositivos/sesiones activas;
- exportación o borrado;
- privacidad y consentimiento;
- soporte o contacto;
- versión y canal de release como sección de ayuda.

### 8.11 Caché y offline

El móvil usa caché por usuario y un modelo cache-first/stale-while-revalidate para dashboard, historial, plantillas, alimentos habituales y chat.

Las cachés nutricional y de conversaciones tienen una caducidad actual de siete días. No deben interpretarse como almacenamiento local indefinido.

Cuando hay datos:

- se muestran inmediatamente;
- el refresco ocurre en segundo plano;
- un fallo de refresco no borra el contenido visible;
- solicitudes simultáneas se deduplican;
- mutaciones deterministas pueden actualizar y revertir localmente.

No es un producto offline-first completo:

- agente, voz, búsqueda, propuestas y drafts necesitan backend;
- no hay cola de cambios;
- no hay sincronización diferida;
- no hay un estado global de desconexión;
- la restauración de sesión puede impedir usar datos cacheados después de un arranque sin red.

### 8.12 Idiomas y accesibilidad

La app soporta inglés y español y envía el locale al backend. Persiste el idioma y ofrece tema claro/oscuro/sistema.

Pendientes:

- respetar el idioma inicial del sistema;
- eliminar cadenas residuales en inglés;
- localizar todos los formatos de fecha;
- corregir controles táctiles ya identificados por debajo de 44–48 píxeles, incluidos los botones de hidratación de `34×34`;
- resolver que Flutter fuerce orientación vertical mientras la configuración iOS también declara landscape;
- validar tablet/iPad una vez resuelta la política de orientación;
- cerrar permisos y configuración iOS.

La accesibilidad es, por tanto, **parcial**: existen Semantics, tooltips y soporte de reducción de movimiento en recorridos importantes, pero quedan controles subdimensionados conocidos.

---

## 9. Nutrición, objetivos y datos

### 9.1 Objetivos nutricionales

El producto maneja:

- objetivo calórico diario;
- proteína, carbohidratos y grasa;
- macros por porcentaje o gramos;
- presets equilibrado, alto en proteína y bajo en carbohidratos;
- objetivo y consumo de hidratación;
- snapshots diarios para preservar el contexto histórico.

La calculadora usa Mifflin–St Jeor, factores de actividad y ajustes por objetivo. Es orientativa, opera con guardrails y no sustituye recomendación profesional.

Limitaciones de inclusión y producto:

- el sexo se modela de forma binaria para la fórmula;
- el rango aceptado es adulto;
- no se modelan embarazo, lactancia, patologías, composición corporal ni adaptación metabólica;
- no se guardan los datos del calculador como perfil longitudinal.

### 9.2 Fuentes de alimentos

Orden de prioridad conceptual:

1. alimentos y plantillas confirmados por el usuario;
2. USDA FoodData Central para ingredientes genéricos y porciones;
3. Open Food Facts para productos envasados y códigos de barras;
4. valores manuales explícitos del usuario.

El corpus se importa a PostgreSQL y conserva fuente, identificador, URL, licencia y fecha de ingesta cuando existen. La comida confirmada conserva una procedencia parcial —fuente, identificador externo, URL y licencia—, pero no toda la metadata del corpus.

La auditoría local documentada en mayo de 2026 analizó aproximadamente 1,3 millones de filas y consideró válidas alrededor de 1,01 millones. Es una medición de un corpus local, no una garantía sobre el entorno productivo actual.

### 9.3 Calidad y búsqueda

El sistema incluye:

- filtros de calidad;
- detección de duplicados y sospechosos;
- documentos de búsqueda normalizados;
- búsqueda exacta por barcode;
- full-text search;
- trigram/fuzzy;
- ranking por fuente, calidad y preferencias del usuario;
- validación de porciones;
- aclaraciones cuando la confianza es insuficiente.

La búsqueda normalizada avanzada está gobernada por feature flags y puede estar desactivada por defecto. La infraestructura vectorial de alimentos existe, pero no está conectada al flujo normal: el repositorio necesita que el caller aporte un embedding y el `FoodResolver` actual no lo hace. No debe presentarse todavía como búsqueda semántica activa.

### 9.4 Personalización

Las señales de selección, registro y corrección pueden alimentar afinidad y ranking. Las comidas habituales y alias son hoy la forma de personalización más concreta.

La visión de “memoria que mejora” está solo parcialmente realizada:

- los aliases y plantillas funcionan;
- existen tablas de memoria y embeddings;
- el servicio de recuperación vectorial no completa la consulta semántica en runtime;
- contadores de uso de algunas memorias no se actualizan de forma observable.

### 9.5 Riesgos de exactitud

- Datos públicos incompletos o inconsistentes.
- Diferencias entre crudo/cocinado y porciones domésticas.
- Ambigüedad de marcas, recetas y unidades.
- Entradas manuales erróneas.
- Valores de una etiqueta mal reconocidos por OCR.
- Resumen diario calculado con límites UTC, que puede desplazar comidas cerca de medianoche en otras zonas horarias.
- Posible expectativa excesiva si el copy presenta la estimación como certeza.

Regla de producto: cuando la resolución no es suficientemente segura, el sistema debe pedir aclaración o permitir entrada explícita; no debe completar nutrición inventada.

---

## 10. Agente, voz y capa de acciones

### 10.1 Arquitectura conceptual

```text
Flutter / futuro adaptador del sistema operativo
  -> API autenticada
  -> agente y/o acción canónica
  -> executor backend controlado
  -> repositorio nutricional y PostgreSQL
  -> respuesta estructurada y auditable
```

### 10.2 Responsabilidades del agente

El agente puede:

- interpretar una frase;
- elegir una herramienta permitida;
- solicitar una búsqueda;
- crear una propuesta;
- revisar una propuesta activa;
- consultar resumen, historial, restantes y habituales;
- preparar borradores para revisión.

El agente no debe:

- escribir directamente en PostgreSQL;
- inventar valores nutricionales autoritativos;
- saltarse permisos;
- modificar alimentos habituales sin revisión de UI;
- ejecutar acciones destructivas de forma autónoma.

### 10.3 Acciones canónicas implementadas

- consultar memoria de alimentos;
- buscar nutrición;
- proponer una comida;
- crear propuesta desde ítems;
- confirmar comida;
- corregir comida;
- revisar propuesta;
- eliminar comida;
- obtener resumen diario;
- obtener objetivos restantes;
- obtener historial;
- listar/crear/actualizar/eliminar alimentos habituales;
- listar, generar borrador, crear, actualizar y eliminar comidas habituales.

### 10.4 Confirmación y seguridad

La propuesta previa al commit es un control central, pero la infraestructura de confirmación no está cerrada como mecanismo general del servidor:

- existe metadata de `confirmationRequired`;
- borrar requiere una confirmación literal específica;
- commit y corrección confían en el flujo que llama a la acción;
- la tabla de solicitudes de confirmación no tiene uso runtime observable;
- no hay un token general de confirmación asociado a todas las escrituras.

Además, el commit de una propuesta no implementa una garantía de idempotencia completa. Un retry mal coordinado podría crear duplicados.

### 10.5 Trusted auto-commit

La visión describe un modo opcional para comidas habituales de alta confianza. El backend conserva flags, umbrales y lógica relacionada, pero en el baseline:

- el usuario no dispone de un control normal visible;
- el contexto de acción fuerza el modo de confianza a desactivado;
- los tests actuales conservan el comportamiento de propuesta.

Estado: **no operativo como capacidad de usuario**.

Decisión recomendada: o se elimina del mensaje de producto a corto plazo, o se rediseña como una feature completa con opt-in, elegibilidad, undo, auditoría e idempotencia.

### 10.6 Voz y proveedores

- El dispositivo graba audio.
- El backend valida tamaño y formato.
- La transcripción usa una API compatible con Whisper; la configuración actual apunta a Groq.
- El agente usa OpenRouter con modelo y routing configurables.
- El audio no parece persistirse como bytes en la base de datos.
- La transcripción completa sí puede persistirse en telemetría y conversaciones.

Dependencias de negocio:

- disponibilidad y precio de OpenRouter/modelos;
- disponibilidad y precio de Groq/STT;
- latencia de red;
- tratamiento legal de datos por terceros;
- capacidad de cambiar de proveedor sin rediseñar el producto.

La arquitectura define abstracciones, pero no existe un failover multi-provider plenamente operativo.

OpenRouter sí puede enrutar entre proveedores upstream mediante su opción de fallbacks. Esto no equivale a redundancia independiente frente a una caída del propio gateway, ni ofrece un segundo proveedor STT.

### 10.7 Prompt injection y entradas adversariales

El executor limita el alcance mediante schemas, permisos y herramientas permitidas, pero el LLM consume texto del usuario y resultados de herramientas. La confirmación general server-side todavía no aporta una prueba fuerte para cada commit/corrección.

Antes de ampliar automatización se necesitan:

- threat model de prompt injection directa e indirecta;
- evals adversariales multilingües;
- filtrado y serialización estricta de tool results;
- confirmación server-side para escrituras sensibles;
- límites de iteración, coste y repetición;
- revisión de logs para detectar intentos de escalada.

### 10.8 Historial de chat

Las conversaciones y mensajes se guardan y pueden reanudarse. En móvil, una conversación inconclusa o reciente puede recuperarse al volver.

“Eliminar conversación” la oculta al usuario mediante `hidden_from_user_at`; no borra los mensajes físicamente y el panel administrativo puede incluir contenido oculto. Las comidas, alimentos habituales y plantillas también usan borrado lógico en el runtime. Ninguna de estas operaciones asegura supresión física. El copy, la privacidad y la política de retención deben reflejar esta realidad o cambiarla.

---

## 11. Arquitectura técnica resumida

### 11.1 Componentes

| Componente | Tecnología | Responsabilidad |
| --- | --- | --- |
| App móvil | Flutter/Dart | UI, estado, caché, grabación, cámara y cliente API. |
| Backend | Bun/TypeScript/Hono | Auth, API, agente, acciones, STT, nutrición y telemetría. |
| Contratos | TypeScript/Zod/OpenAPI | Esquemas compartidos y generación de cliente. |
| Base de datos | PostgreSQL 16 + pgvector | Fuente de verdad, búsqueda, memoria y auditoría. |
| Landing/admin | HTML/CSS/JS estático | Marketing, descarga y operación. |
| IA | OpenRouter por defecto en el baseline | Tool calling y estructuración mediante abstracción reemplazable. |
| Voz | Groq compatible con Whisper por defecto | Transcripción mediante abstracción reemplazable. |
| OCR | ML Kit en dispositivo | Extracción de texto de etiquetas. |
| Hosting | VPS, Docker, NGINX, GHCR | Ejecución de dev/pro y publicación. |

### 11.2 Dominios de datos

- usuarios, credenciales, identidades Google y sesiones;
- tokens de recuperación;
- objetivos y snapshots diarios;
- alimentos, porciones, calidad, normalización e importaciones;
- propuestas, comidas e ítems;
- ingredientes y comidas habituales;
- memorias, embeddings y preferencias;
- confirmaciones, correcciones, acciones y auditoría;
- conversaciones, mensajes y candidatos;
- telemetría de API, agente, herramientas, LLM, STT y búsqueda.

Algunas tablas existen como reserva arquitectónica sin uso observable: confirmaciones generalizadas, correcciones como entidad separada, conexiones de agentes, outbox y aliases globales.

### 11.3 API principal

La API implementa grupos para:

- auth y cuenta;
- settings, objetivos e hidratación;
- catálogo y ejecución de acciones;
- búsqueda y alimentos habituales;
- plantillas;
- agente texto/audio y conversaciones;
- transcripción y voice meal runs;
- propuestas, commit, corrección y borrado;
- resumen e historial;
- telemetría cliente y administración.

Riesgo técnico-producto: el OpenAPI generado está desfasado respecto a rutas reales como chat, audio y parte de auth. Esto puede crear clientes incompletos y documentación falsa.

### 11.4 Cache y consistencia

La app usa datos persistentes por usuario, deduplicación de requests, cooldowns y stale-while-revalidate. Las mutaciones deterministas se optimizan localmente con rollback.

No se aplican actualizaciones optimistas a IA, STT, búsqueda o propuestas cuando el backend produce el resultado final.

---

## 12. Distribución, despliegue y operación

### 12.1 Entornos

- Desarrollo: `https://dev-api.bettercalories.app`
- Producción: `https://api.bettercalories.app`
- Web: `https://bettercalories.app`

La configuración versionada sitúa dev y producción en la misma infraestructura física y una instancia PostgreSQL, con schemas separados. Pueden existir controles externos no representados en Git.

Snapshot operativo verificado el 2026-07-16 mediante los manifiestos de [producción](https://api.bettercalories.app/apk/latest.json) y [desarrollo](https://dev-api.bettercalories.app/apk/latest.json):

- los health checks de dev y producción respondían correctamente;
- producción servía la APK `0.1.5+6`, publicada el 2026-05-25;
- dev servía la APK `0.1.9+21`, publicada el 2026-06-25;
- el código revisado también declara `0.1.9+21`.

La diferencia de versiones confirma que dev y producción no avanzan automáticamente al mismo ritmo. Este snapshot es temporal y debe actualizarse antes de decisiones de release.

### 12.2 Backend

- Dev despliega desde `develop`.
- Producción despliega desde tags `v*`.
- GitHub Actions ejecuta typecheck, tests, build y Docker.
- Las imágenes se publican en GHCR.
- El despliegue es blue/green.
- Las migraciones se ejecutan antes del cambio de tráfico.
- NGINX termina TLS y el backend expone health checks.

El proceso no implementa rollback automático completo: migra el schema compartido antes del cutover, cambia NGINX, detiene el slot anterior y hace después el health check externo. Una migración incompatible o un fallo posterior al cambio puede impedir volver al slot previo. Las migraciones deben ser backward-compatible y necesita un runbook de rollback probado.

### 12.3 Android

- Flavors `dev` y `prod`.
- APK release con checksum y manifiesto `latest.json`.
- Página web de descarga.
- Actualización in-app que abre el APK externo cuando aumenta `versionCode`.
- Workflow manual de compilación y publicación.

Riesgo crítico: el workflow permite `ALLOW_DEBUG_SIGNING=1` también para producción; si no se aporta una keystore release, Gradle usa la firma debug. No se verificó el certificado del APK desplegado durante esta revisión. El pipeline debe demostrar y exigir firma release antes de distribuir a usuarios externos.

### 12.4 iOS

El proyecto contiene target iOS y la visión define iOS 17, pero faltan elementos para considerarlo un canal listo:

- pipeline de App Store integrado;
- cierre de firma y credenciales;
- `NSMicrophoneUsageDescription`; su ausencia puede terminar la app al intentar grabar;
- localización del texto de permiso de cámara, actualmente solo en inglés;
- configuración Google Sign-In;
- estrategia de actualización equivalente;
- coherencia de nombre y orientaciones: Flutter fuerza `portraitUp` mientras el plist declara landscape;
- coherencia del mínimo soportado: la visión fija iOS 17, mientras el proyecto Xcode declara actualmente deployment target 13.0;
- validación de release.

### 12.5 Landing y admin

La landing se despliega por SSH con validación y backup del webroot. El admin es estático y consume endpoints protegidos por credenciales administrativas.

El panel administrativo está configurado para servirse bajo `dev-api`, no bajo la API de producción. Muestra datos especialmente sensibles: conversaciones, transcripciones, tool calls, trazas y costes. Necesita ownership de acceso, auditoría, mínimos privilegios y retención.

### 12.6 Resiliencia y backups

La infraestructura incluye un script manual de `pg_dump` limitado a cada schema dev/pro; no es un backup integral de instancia, roles y extensiones. No hay evidencia versionada de:

- agenda automática;
- cifrado;
- copia off-site;
- política de retención;
- prueba periódica de restore;
- alertas de disco y backup;
- recuperación ante pérdida del VPS.

La arquitectura exige estos controles antes de producción; deben tratarse como gate empresarial, no como mejora opcional.

### 12.7 Calidad y CI

Fortalezas:

- suite amplia de backend;
- tests unitarios, de repositorio, ViewModel y widgets en Flutter;
- tests de contratos, auth, acciones, agente, búsqueda, STT y telemetría;
- proceso blue/green con health check.

Brecha:

- no existe un workflow móvil general que ejecute `flutter analyze` y `flutter test` antes de publicar; el workflow de APK compila y despliega.

---

## 13. Seguridad, privacidad y cumplimiento

### 13.1 Datos tratados

| Categoría | Ejemplos | Destino observable |
| --- | --- | --- |
| Identidad | nombre, email, identidad Google | PostgreSQL y Google durante login. |
| Sesión | access/refresh tokens | Los tokens raw se entregan al cliente y se guardan en almacenamiento seguro; PostgreSQL conserva el hash con pepper del refresh y no persiste el access JWT. |
| Nutrición | objetivos, comidas, porciones, agua | PostgreSQL y caché móvil. |
| Perfil de cálculo | edad, sexo, altura, peso, actividad y meta | enviado al backend para estimación; persistencia de perfil no implementada. |
| Voz | audio grabado | proveedor STT; bytes no persistidos de forma observable. |
| Texto sensible | mensajes de usuario/asistente, transcripciones, contexto y argumentos/resultados de herramientas | conversaciones y telemetría PostgreSQL; texto/contexto también se envía a OpenRouter y modelos downstream. No se afirma persistencia general del system prompt o respuestas crudas completas del proveedor. |
| Telemetría | errores, trazas, latencia, uso y costes | PostgreSQL y panel admin. |
| Imágenes | foto de etiqueta | procesamiento móvil/OCR; el texto puede enviarse al backend. |

### 13.2 Controles existentes

- HTTPS y NGINX.
- CORS allowlist.
- autorización backend para rutas protegidas.
- scoping por usuario en repositorios.
- Argon2id para contraseñas.
- JWT de acceso corto y refresh rotado/hasheado.
- almacenamiento seguro móvil.
- permisos por acción.
- auditoría y trace IDs.
- secretos de proveedores solo en backend.
- autenticación administrativa separada.
- búsqueda telemétrica con hash en algunos flujos.

Son controles observables en código/configuración versionada; deben verificarse de nuevo sobre la infraestructura desplegada.

### 13.3 Brechas críticas

1. No hay política de privacidad pública propia.
2. No hay términos de servicio ni contacto legal visible.
3. No hay consentimiento u opt-out de telemetría sensible.
4. No hay política de retención para chats, transcripciones y telemetría.
5. No hay exportación de datos.
6. No hay borrado integral de cuenta, memorias, embeddings y telemetría identificable.
7. Ocultar un chat no equivale a borrarlo.
8. No hay rate limiting/abuse protection observable para auth, agente o STT.
9. No hay verificación email para cuentas locales.
10. La recuperación de contraseña carece de un delivery productivo visible.
11. No hay evidencia versionada de backups automáticos cifrados y restore probado.
12. El pipeline puede publicar una APK de producción con firma debug; la firma del artefacto desplegado queda pendiente de verificación.
13. No hay MFA administrativo ni política de acceso documentada.
14. No hay cifrado de campos sensibles a nivel aplicación observable.
15. El linking automático local→Google permite un escenario de account takeover si el email local no está verificado.
16. El NGINX versionado no añade HSTS ni un conjunto completo de cabeceras defensivas para web/admin.
17. Los workflows confían en `ssh-keyscan` en cada despliegue en vez de fijar la host key del VPS.

### 13.4 Proveedores y subencargados a documentar

- proveedor de hosting/VPS;
- OpenRouter y modelos servidos;
- Groq/STT;
- Google Sign-In;
- GitHub/GHCR y CI;
- Apple/Google si se entra en stores;
- cualquier servicio futuro de email, errores, analítica o pagos.

### 13.5 Licencias de datos

- Según la documentación del importador, Open Food Facts requiere atribución y cumplimiento ODbL, incluidas obligaciones de share-alike según el uso.
- La documentación de USDA FoodData Central se trata como dominio público/CC0.
- BEDCA se mantiene fuera del runtime porque el repositorio no considera suficiente su licencia para redistribución abierta.

Estas notas no son un dictamen legal. Validar licencias, atribución y redistribución con asesoramiento antes de comercializar o exponer datasets derivados.

### 13.6 Posición médica

Better Calories es una herramienta de seguimiento personal. No debe:

- diagnosticar;
- tratar;
- prescribir;
- prometer pérdida o ganancia concreta;
- presentarse como sustituto de un profesional sanitario;
- inducir a interpretar una estimación calórica como necesidad médica exacta.

---

## 14. Telemetría, analítica y aprendizaje

### 14.1 Lo que se mide hoy

- requests, errores y trazas de backend;
- búsquedas de alimentos, resultados cero y confianza;
- ejecuciones y turnos LLM;
- tool calls y action calls;
- tokens, latencia y coste;
- transcripciones y estados STT;
- conversaciones y mensajes;
- parte de los eventos móviles, caché y flujos de voz.

### 14.2 Lo que falta para dirigir el negocio

- adquisición y fuente de alta;
- conversión landing → descarga → instalación → registro;
- activación;
- tiempo hasta primera comida confirmada;
- propuesta vista, editada, confirmada o abandonada;
- uso comparado de manual, texto, voz, habitual y OCR;
- retención D1/D7/D30 o W1/W4;
- recurrencia por cohorte;
- frecuencia de registro;
- coste por comida confirmada;
- coste mensual por usuario activo;
- intención de pago y conversión a plan;
- motivos de abandono;
- satisfacción y confianza percibida.

### 14.3 North Star propuesta

**Recomendación**:

> Comidas confirmadas por usuario activo semanal que no requieren una corrección inmediata.

Esta métrica combina utilidad, frecuencia y calidad. No debe optimizarse aislada: podría aumentar por registros triviales o por usuarios obsesivos.

Guardrails:

- corrección o eliminación dentro de 10 minutos;
- propuestas abandonadas;
- errores y baja confianza;
- tiempo mediano y p90 de registro;
- coste IA/STT por comida confirmada;
- retención W1 y W4;
- quejas de privacidad o soporte;
- uso saludable y ausencia de copy culpabilizador.

### 14.4 Funnel recomendado

```text
visita landing
  -> descarga
  -> instalación
  -> registro/login
  -> objetivo configurado
  -> primera propuesta
  -> primera comida confirmada
  -> primer habitual reutilizado
  -> 3 días con registro en una semana
  -> retención W4
  -> conversión a pago futura
```

### 14.5 Métricas de producto prioritarias

| Dimensión | Métrica |
| --- | --- |
| Activación | % que confirma primera comida en 24 h. |
| Time-to-value | Minutos desde alta hasta primera comida. |
| Velocidad | Tiempo desde intención hasta commit por modalidad. |
| Calidad | Confirmado sin edición y corrección inmediata. |
| Resolución | Zero-result, low-confidence y aclaraciones por búsqueda. |
| Voz | Inicio → audio válido → transcript → propuesta → commit. |
| Recurrencia | % que reutiliza habitual en 7/30 días. |
| Retención | D1, D7, D30, W4 por cohorte y modalidad inicial. |
| Economía | Coste LLM+STT por comida y por MAU. |
| Fiabilidad | Errores, latencia, crash-free sessions y rollback. |
| Confianza | Eliminaciones/correcciones, soporte y encuesta cualitativa. |

### 14.6 Investigación cualitativa mínima

Durante la beta, entrevistar y observar a usuarios para responder:

- ¿Qué método de registro eligen espontáneamente?
- ¿Dónde dudan antes de confirmar?
- ¿Qué errores destruyen la confianza?
- ¿Crean habituales o esperan que el sistema los aprenda solo?
- ¿La voz se usa en público, casa, coche o gimnasio?
- ¿Qué significa “preciso” para ellos?
- ¿Qué pagarían por voz, memoria o ahorro de tiempo?
- ¿Qué datos no aceptarían que se almacenasen?

---

## 15. Modelo de negocio y economía

### 15.1 Estado actual

No hay evidencia de:

- planes;
- precios;
- suscripciones;
- compras in-app;
- Stripe, RevenueCat, Play Billing o StoreKit;
- cuotas de uso;
- paywall;
- entitlements;
- facturación;
- revenue analytics.

Ingresos, usuarios activos, churn y willingness to pay son **desconocidos**.

### 15.2 Costes variables relevantes

- llamadas LLM por turno y herramientas;
- transcripción de audio;
- embeddings si se activan;
- almacenamiento y backups;
- transferencia de APK y API;
- soporte de usuarios;
- Apple/Google y servicios futuros;
- revisión de calidad del corpus nutricional.

La telemetría LLM ya puede separar coste reportado, estimado y desconocido por proveedor, modelo, usuario, conversación y feature. Falta incorporar de forma fiable STT, embeddings, infraestructura y soporte, y traducirlo todo a coste por resultado de negocio.

### 15.3 Unidad económica recomendada

```text
coste variable por comida confirmada =
  coste LLM + coste STT + coste embedding atribuible + infraestructura variable

coste mensual por usuario activo =
  suma de costes variables del usuario + asignación de infraestructura/soporte

margen bruto por usuario =
  ingreso neto del plan - coste mensual por usuario activo
```

No fijar una suscripción ilimitada antes de conocer la cola de usuarios intensivos y el p90/p99 de coste.

### 15.4 Opciones de monetización a probar

No son decisiones tomadas:

1. **Núcleo manual gratuito + IA limitada.** Búsqueda, diario y objetivos gratuitos; voz/agente con cuota.
2. **Freemium por volumen.** Número incluido de registros inteligentes al mes.
3. **Suscripción premium.** Voz, memoria avanzada, OCR y analítica longitudinal.
4. **Beta gratuita con límites transparentes.** Antes de poner precio, medir retención y coste.

### 15.5 Recomendación de secuencia

1. Medir coste por comida confirmada y por WAU.
2. Segmentar usuarios por intensidad y modalidad.
3. Entrevistar sobre willingness to pay.
4. Definir el núcleo gratuito que preserva utilidad.
5. Probar límites y copy antes de integrar pagos.
6. Integrar stores y entitlements de forma compatible con Apple/Google.

### 15.6 Hipótesis de moat

La IA por sí sola no es una ventaja defendible. El moat potencial sería:

- corpus local limpio y bien rankeado;
- personalización por usuario;
- comidas habituales y correcciones acumuladas;
- resolución de alimentos regionales;
- action layer reutilizable y segura;
- dataset de fallos, candidatos y decisiones para mejorar la experiencia.

Esta ventaja solo aparece si se mantienen calidad, privacidad, portabilidad y aprendizaje real.

---

## 16. Diagnóstico estratégico

### 16.1 Fortalezas

- Propuesta de valor concreta y fácil de demostrar.
- Núcleo funcional más avanzado que un prototipo temprano.
- Acción estructurada y confirmación como principio arquitectónico.
- Voz, texto, búsqueda, OCR y habituales en un mismo producto.
- Fuentes nutricionales y procedencia.
- Buen patrón móvil de caché y UI optimista.
- Telemetría profunda de IA, herramientas y costes.
- Interfaces de proveedor parcialmente desacopladas; el wiring productivo sigue centrado en OpenRouter y Groq.
- Backend y despliegue controlados por el equipo.

### 16.2 Debilidades

- Recorrido principal fragmentado entre agente, creación manual, voz y habituales.
- Onboarding débil y perfil incompleto.
- Analítica empresarial insuficiente.
- Ausencia de monetización.
- Distribución mediante sideload.
- iOS sin cierre comercial.
- Privacidad, retención y derechos del usuario incompletos.
- Memory/vector y trusted mode por debajo de la visión.
- Deuda de localización y naming.
- Punto único de fallo operativo.

### 16.3 Oportunidades

- Ganar el caso de uso de comidas recurrentes antes de ampliar el producto.
- Convertir correcciones y habituales en personalización útil.
- Usar coste por acción para diseñar un plan sostenible.
- Posicionarse por confianza y control en vez de “IA”.
- Mejorar cobertura España/UE de productos y porciones.
- Llevar la experiencia a stores cuando los gates estén cerrados.
- Exponer acciones a sistemas operativos sin duplicar lógica.

### 16.4 Amenazas

- Comoditización de chat y reconocimiento de voz.
- Desconfianza por errores nutricionales.
- Riesgo legal por datos de salud adyacentes y transcripciones.
- Dependencia de proveedores y cambios de precio.
- Coste alto de usuarios intensivos.
- Restricciones de stores a pagos, privacidad o permisos.
- Incidentes de base de datos en infraestructura única.
- Fricción de sideload y firma.
- Competidores con distribución, marca y catálogos consolidados.

La comparación competitiva específica no forma parte de este snapshot. Requiere investigación externa de mercado, precios, retención y posicionamiento.

---

## 17. Decisiones empresariales pendientes

### 17.1 Registro de gobernanza

Las tablas siguientes describen qué decidir, pero cada decisión necesita un registro operativo. Mientras el equipo no asigne responsables y fechas, su estado es abierto.

| ID | Ámbito | Responsable | Fecha objetivo | Estado | Decisión adoptada | Evidencia |
| --- | --- | --- | --- | --- | --- | --- |
| D-001 | Privacidad y base jurídica | Por asignar | Antes de ampliar beta | Abierta | Pendiente | Política, revisión legal y registro de consentimiento/base aplicable. |
| D-002 | Derechos de datos | Por asignar | Antes de ampliar beta | Abierta | Pendiente | Exportación/borrado probados. |
| D-003 | Integridad nutricional | Por asignar | Antes de ampliar beta | Abierta | Pendiente | Idempotencia, timezone y tests. |
| D-004 | Continuidad operativa | Por asignar | Antes de ampliar beta | Abierta | Pendiente | Backup/restore y controles de acceso. |
| D-005 | Distribución | Por asignar | Antes de siguiente prod | Abierta | Pendiente | Firma release, canal y checklist. |
| D-006 | Métricas e ICP | Por asignar | Antes de siguiente cohorte | Abierta | Pendiente | Funnel, North Star y cohortes. |
| D-007 | Recorrido principal | Por asignar | Antes de rediseño mayor | Abierta | Pendiente | Decisión producto/diseño con experimento. |
| D-008 | Monetización | Por asignar | Después de evidencia W4/costes | Abierta | Pendiente | Pricing, límites y unit economics. |

Estados permitidos: `Abierta`, `En análisis`, `Decidida`, `En ejecución`, `Validada` o `Revertida`. Toda decisión `Decidida` debe incluir responsable, fecha, alternativa descartada y enlace a evidencia o ADR.

### 17.2 Prioridad P0: antes de ampliar la beta

| ID | Decisión | Pregunta | Recomendación inicial | Evidencia de cierre |
| --- | --- | --- | --- | --- |
| D-001 | Privacidad | ¿Qué se recoge, por qué y durante cuánto? | Publicar política y mapa de proveedores. | Legal revisado y visible en web/app. |
| D-001 | Base jurídica y controles | ¿Se pueden almacenar chats/transcripciones por defecto? | Definir la base jurídica con asesoramiento; obtener consentimiento explícito y ofrecer controles cuando corresponda. | Registro versionado de la base y preferencias aplicables. |
| D-002 | Derechos | ¿Cómo exporta o borra el usuario? | Implementar exportación y borrado integral. | Test end-to-end y runbook. |
| D-004 | Backups | ¿Cómo se recupera una pérdida del VPS? | Backup cifrado off-site y restore probado. | Restore documentado con RPO/RTO. |
| D-005 | Firma Android | ¿Qué clave firma producción? | Bloquear publicación sin release keystore. | CI falla si detecta debug. |
| D-003 | Integridad de escritura | ¿Cómo se evitan duplicados por retry? | Idempotency keys y unicidad por propuesta. | Tests de retry concurrente. |
| D-003 | Día nutricional | ¿Qué fecha aplica en cada timezone? | Calcular límites con timezone autenticada. | Tests cerca de medianoche y DST. |
| D-005 | Calidad móvil | ¿Qué valida una APK antes de publicar? | Ejecutar `flutter analyze` y `flutter test` en CI. | Workflow requerido y bloqueante. |
| D-004 | Abuso | ¿Cómo se limitan auth, STT y LLM? | Rate limits por IP/usuario y cuotas. | Tests y alertas. |
| D-004 | Acceso admin | ¿Quién puede leer conversaciones? | Mínimos privilegios, MFA o equivalente y auditoría. | Política y logs de acceso. |
| D-002 | Cuenta | ¿Cómo se recupera y verifica email? | Email transaccional, reset móvil y verificación. | Flujo productivo probado. |
| D-002 | Linking de identidad | ¿Cómo se enlazan Google y cuenta local? | No enlazar por email no verificado; exigir reautenticación/consentimiento o rechazar conflicto. | Tests de preregistro hostil y linking legítimo. |
| D-004 | Rollback | ¿Cómo se revierte un deploy tras migrar? | Migraciones backward-compatible y runbook probado. | Simulacro de rollback con datos. |
| D-004 | Hardening de deploy | ¿Cómo se confía en el VPS? | Fijar host key y añadir cabeceras defensivas. | Pinning y verificación automatizada. |

### 17.3 Prioridad P1: demostrar valor

| Decisión | Pregunta | Recomendación inicial |
| --- | --- | --- |
| ICP | ¿Para quién se optimiza primero? | Adulto España/UE con comidas repetitivas y seguimiento de macros. |
| Activación | ¿Cuál es el primer éxito? | Primera comida confirmada en 24 h. |
| Recorrido principal | ¿Agente o creación manual? | Agente como entrada rápida; editor estructurado como control y fallback. |
| North Star | ¿Qué comportamiento representa valor recurrente? | Comidas confirmadas por WAU sin corrección inmediata. |
| Onboarding | ¿Qué debe ocurrir antes del dashboard? | Explicar valor y guiar a objetivo + primera comida, con skip. |
| Habituales | ¿Se crean o se infieren? | Crear tras valor inicial y sugerir guardado después de repeticiones. |
| Analytics | ¿Qué funnel se instrumenta? | Alta → objetivo → propuesta → commit → reutilización → W4. |
| Calidad | ¿Qué error es inaceptable? | Nutrición inventada, duplicado por retry y fecha diaria incorrecta. |

### 17.4 Prioridad P2: comercializar

| Decisión | Pregunta | Recomendación inicial |
| --- | --- | --- |
| Canal | ¿APK, Play Store o ambos? | Play Store para beta amplia; APK solo para canales controlados. |
| iOS | ¿Android-first o simultáneo? | Android-first hasta cerrar gates; fijar un hito explícito para iOS. |
| Precio | ¿Qué se cobra? | Basarlo en retención y coste real, no en número de features. |
| Límite IA | ¿Qué uso incluye cada plan? | Cuota o fair-use medible, con núcleo manual útil. |
| Promoción | ¿Cómo pasa dev a prod? | Checklist y cadencia de release definidos. |
| Soporte | ¿Dónde reporta problemas el usuario? | Canal in-app/web con trace ID y SLA de beta. |

### 17.5 Prioridad P3: expansión

- trusted auto-commit seguro;
- memoria semántica completa;
- AppFunctions/App Intents;
- tendencias y peso;
- integraciones de salud;
- recordatorios y widgets;
- profesional/B2B;
- nuevos idiomas y mercados.

Estas opciones no deben competir con la validación del núcleo sin evidencia clara.

---

## 18. Hoja de ruta por gates

Esta hoja de ruta es una propuesta de secuencia, no un compromiso de fechas.

### Gate A — Beta privada segura

Objetivo: que un grupo controlado use el producto sin riesgos empresariales evitables.

Requisitos:

- eliminar credenciales demo;
- privacidad, términos y contacto;
- consentimiento y retención;
- exportación y borrado;
- reset/verificación de cuenta;
- linking seguro entre cuenta local y Google;
- rate limiting;
- firma release obligatoria;
- backups cifrados y restore;
- CI móvil con analyze/test;
- corrección de zona horaria e idempotencia;
- migraciones backward-compatible y rollback probado;
- threat model y evals de prompt injection;
- acceso admin controlado.

### Gate B — Evidencia de producto

Objetivo: demostrar que Better Calories mejora el registro recurrente.

Requisitos:

- ICP y cohorte definidos;
- onboarding medible;
- funnel de activación;
- comparación de tiempo manual/texto/voz/habitual;
- calidad de propuestas y correcciones;
- W1/W4;
- coste por comida/WAU;
- entrevistas de confianza y willingness to pay;
- decisión sobre recorrido principal.

### Gate C — Comercialización

Objetivo: adquirir usuarios y cobrar con economía entendida.

Requisitos:

- canal Play Store o equivalente;
- política de release y soporte;
- pricing experimentable;
- entitlements y límites;
- analítica de conversión;
- separación razonable de entornos y plan de escalado;
- contenido comercial validado y legalmente consistente.

### Gate D — Expansión de plataforma

Objetivo: ampliar valor sin duplicar la lógica del producto.

Opciones:

- iOS productivo;
- integraciones del sistema operativo;
- memoria semántica real;
- tendencias longitudinales;
- integraciones de salud;
- canales profesionales.

---

## 19. Riesgos priorizados

| Prioridad | Riesgo | Impacto | Mitigación principal |
| --- | --- | --- | --- |
| Crítica | Datos sensibles sin política/consentimiento/retención | Legal, reputación y confianza | Cerrar programa de privacidad antes de escalar. |
| Crítica | Linking Google a cuenta local con email no verificado | Account takeover | Verificar email y exigir linking seguro. |
| Crítica | Solo hay evidencia versionada de backup manual, sin cifrado/restore automatizado | Pérdida irreversible | Backup automático off-site y restore. |
| Crítica | El pipeline permite publicar prod con firma debug; firma desplegada no verificada | Seguridad y distribución | Release signing obligatoria y comprobación de certificado en CI. |
| Alta | Sin rate limits en auth/LLM/STT | Fraude, coste y disponibilidad | Límites, cuotas y alertas. |
| Alta | Sin borrado/exportación integral | Cumplimiento y confianza | Endpoints, UI y limpieza en cascada. |
| Alta | Commit no idempotente | Duplicados de comidas | Unique/idempotency keys y tests. |
| Alta | Día calculado en UTC | Resúmenes incorrectos | Límites por timezone del usuario. |
| Alta | Sesión offline limpia tokens | Pérdida de acceso y confianza | Distinguir auth inválida de fallo de red. |
| Alta | Dependencia OpenRouter/Groq | Interrupción y coste | Timeouts, cuotas, fallback y UX degradada. |
| Alta | Prompt injection con confirmación server-side incompleta | Escritura no deseada o fuga de contexto | Threat model, evals y confirmación fuerte. |
| Alta | Blue/green sin rollback automático tras migración | Caída prolongada o schema incompatible | Migraciones compatibles y simulacro de rollback. |
| Alta | Analítica de negocio incompleta | Decisiones sin evidencia | Funnel y cohortes. |
| Media | Producto fragmentado | Confusión y menor activación | Jerarquizar recorrido principal. |
| Media | OpenAPI desfasado | Clientes y docs inconsistentes | Generación y diff en CI. |
| Media | Localización incompleta | Calidad percibida | Eliminar strings hardcoded y testear. |
| Media | iOS incompleto | Promesa comercial incoherente | No anunciar disponibilidad hasta gate. |
| Media | Memoria semántica parcial | Expectativa no cumplida | Limitar copy o completar runtime. |
| Media | Un solo VPS/Postgres | Radio de fallo alto | Backups, monitoring y plan de separación. |

---

## 20. No objetivos actuales

Salvo decisión empresarial posterior, no forman parte del foco inmediato:

- recomendaciones médicas;
- dietas terapéuticas;
- micronutrientes clínicos;
- nutricionista dashboard;
- wearables;
- web app completa;
- escritorio;
- marketplace;
- red social;
- gamificación competitiva;
- reconocimiento general de platos por fotografía;
- microservicios;
- Android AppFunctions/iOS App Intents como requisito de uso;
- expansión masiva de idiomas antes de cerrar inglés/español;
- autonomía destructiva del agente.

---

## 21. Información empresarial no presente

El equipo debe completar fuera del código o añadir aquí:

| Tema | Estado |
| --- | --- |
| Entidad legal y país | Desconocido. |
| Propiedad y cap table | Desconocido. |
| Tamaño y roles del equipo | Desconocido. |
| Presupuesto y runway | Desconocido. |
| Usuarios registrados/activos | Desconocido. |
| Cohortes y retención | Desconocido. |
| Ingresos | Desconocido. |
| Coste total mensual de infraestructura | Desconocido. |
| Soporte y SLA | Desconocido. |
| Política de incidentes | Desconocido. |
| RPO/RTO | Desconocido. |
| Países realmente abiertos | Desconocido. |
| Investigación competitiva | No incluida. |
| Estrategia fiscal/pagos | No definida. |
| Objetivo de lanzamiento | No definido en el baseline. |

---

## 22. Glosario

| Término | Definición |
| --- | --- |
| Acción canónica | Contrato backend con esquema, permisos, política y ejecución controlada; puede ser determinista o asistida por agente. |
| Agente | Servicio LLM que interpreta mensajes y selecciona herramientas permitidas. |
| Commit | Escritura definitiva de una propuesta como comida. |
| Food resolver | Componente que busca y puntúa candidatos nutricionales. |
| Habitual | Ingrediente o comida guardada por el usuario para reutilizar. |
| LLM | Modelo de lenguaje usado para interpretación y tool calling. |
| Macro | Proteína, carbohidratos o grasa. |
| OCR | Reconocimiento óptico de caracteres usado sobre etiquetas. |
| Propuesta | Representación estructurada y revisable anterior al guardado. |
| Provenance | Fuente, identificador y contexto de un valor nutricional. |
| STT | Speech-to-text; transcripción de voz a texto. |
| Stale-while-revalidate | Mostrar caché inmediatamente y refrescar en segundo plano. |
| Trusted mode | Concepto de autoconfirmación para acciones familiares de alta confianza; no operativo hoy. |
| WAU | Usuario activo semanal. |

---

## 23. Fuentes principales del repositorio

### Producto y arquitectura

- [`docs/app-description.md`](docs/app-description.md)
- [`docs/README.md`](docs/README.md)
- [`docs/db-vector-architecture.md`](docs/db-vector-architecture.md)
- [`docs/calorie-estimation-methodology.md`](docs/calorie-estimation-methodology.md)
- [`docs/app-language-localization.md`](docs/app-language-localization.md)
- [`docs/macro-wizard.md`](docs/macro-wizard.md)

### Móvil

- [`apps/mobile/lib/app/router.dart`](apps/mobile/lib/app/router.dart)
- [`apps/mobile/lib/ui/core/app_shell.dart`](apps/mobile/lib/ui/core/app_shell.dart)
- [`apps/mobile/lib/ui/features`](apps/mobile/lib/ui/features)
- [`apps/mobile/lib/data/repositories/nutrition_repository.dart`](apps/mobile/lib/data/repositories/nutrition_repository.dart)
- [`apps/mobile/lib/data/services/nutrition_cache_store.dart`](apps/mobile/lib/data/services/nutrition_cache_store.dart)
- [`apps/mobile/lib/l10n`](apps/mobile/lib/l10n)
- [`apps/mobile/pubspec.yaml`](apps/mobile/pubspec.yaml)
- [`apps/mobile/README.md`](apps/mobile/README.md)

### Backend, contratos y datos

- [`apps/backend/src/http/app.ts`](apps/backend/src/http/app.ts)
- [`apps/backend/src/actions/executor.ts`](apps/backend/src/actions/executor.ts)
- [`apps/backend/src/agent`](apps/backend/src/agent)
- [`apps/backend/src/nutrition`](apps/backend/src/nutrition)
- [`apps/backend/src/repository/postgres.ts`](apps/backend/src/repository/postgres.ts)
- [`apps/backend/src/db/schema.ts`](apps/backend/src/db/schema.ts)
- [`packages/contracts/src`](packages/contracts/src)
- [`infra/db`](infra/db)
- [`tools`](tools)

### Negocio, operaciones y distribución

- [`apps/landing/index.html`](apps/landing/index.html)
- [`apps/landing/README.md`](apps/landing/README.md)
- [`apps/admin/README.md`](apps/admin/README.md)
- [`apps/admin/index.html`](apps/admin/index.html)
- [`specs/admin-telemetry-launch-week-priorities.md`](specs/admin-telemetry-launch-week-priorities.md)
- [`.github/workflows`](.github/workflows)
- [`infra/deploy`](infra/deploy)
- [`scripts/mobile`](scripts/mobile)

---

## 24. Mantenimiento del documento

Actualizar `PRODUCT.md` cuando cambie alguno de estos elementos:

- propuesta de valor o ICP;
- capacidad que pase de planificada a implementada;
- canal de distribución;
- política de privacidad o retención;
- pricing y planes;
- North Star o funnel;
- proveedor crítico;
- arquitectura que afecte comportamiento o coste;
- riesgo P0/P1;
- decisión empresarial cerrada.

En cada actualización:

1. cambiar `last_updated` y, si corresponde, `baseline_commit`;
2. separar hechos de recomendaciones;
3. enlazar la fuente propietaria;
4. retirar promesas que ya no sean ciertas;
5. mover decisiones cerradas a una sección histórica o ADR;
6. revisar que la landing y el producto no prometan más que el runtime;
7. mantener una sola definición oficial de etapa, ICP y North Star.

Este documento debe revisarse como mínimo antes de:

- ampliar la beta;
- publicar en una store;
- introducir pagos;
- cambiar de proveedor de IA/STT;
- abrir un nuevo país;
- procesar nuevas categorías de datos;
- anunciar una capacidad de automatización.
