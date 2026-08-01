# Cabeceras web y origen seguro del panel admin

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: Nginx, panel admin, navegador
- Prioridad: Alta

## Resumen

Reducir ataques en navegador mediante cabeceras defensivas y evitar que el token administrativo pueda enviarse a un origen arbitrario configurado por el usuario.

## Problema y motivación

Un panel privilegiado necesita una frontera de origen estricta. La ausencia de HSTS/CSP y la configuración libre del API base amplían el efecto de inyección, error humano o manipulación local.

## Contexto actual verificado

Las configuraciones en `infra/deploy/nginx/` no establecen HSTS, CSP, `nosniff`, política de framing, referrer o permisos, ni ocultan explícitamente la versión. `apps/admin/app.js` persiste un API base configurable y el token en `sessionStorage`; existen sinks `innerHTML`, aunque no se demostró una explotación directa.

## Objetivos

- Fijar los orígenes administrativos permitidos por entorno.
- Aplicar cabeceras compatibles y restrictivas al panel y la API.
- Eliminar o encapsular sinks HTML innecesarios.

## Requisitos funcionales

- El token admin solo debe adjuntarse a orígenes HTTPS aprobados.
- La allowlist del panel se limitará a localhost de desarrollo y los orígenes oficiales de dev y producción.
- Cambiar de origen debe limpiar o requerir reautenticación antes de reutilizar credenciales.
- Nginx debe aplicar HSTS a los hosts HTTPS correspondientes, sin `preload` ni `includeSubDomains` durante el MVP.
- CSP, `X-Content-Type-Options`, política de frame, referrer y permisos deben cubrir las necesidades reales del panel.
- El render de mensajes debe usar texto o sanitización explícita.

## Criterios de aceptación

- Un origen no aprobado nunca recibe el header administrativo.
- Pruebas automatizadas verifican las cabeceras en dev/prod y rutas de error.
- El panel funciona con CSP sin excepciones amplias como `unsafe-eval`.
- Cambiar el API base no transporta silenciosamente una sesión previa.

## Impacto previsto en el proyecto

Nginx, configuración y JavaScript del panel, tests de despliegue y documentación operativa.

## Decisiones confirmadas

- El selector de API queda restringido a localhost, dev y producción; no aceptará orígenes arbitrarios.
- Cambiar de origen elimina el token administrativo y exige autenticarse de nuevo.
- Se añadirán CSP, `X-Content-Type-Options`, protección contra framing, `Referrer-Policy` y una `Permissions-Policy` mínima para capacidades no utilizadas.
- HSTS no usará `preload` ni abarcará automáticamente todos los subdominios durante el MVP.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
