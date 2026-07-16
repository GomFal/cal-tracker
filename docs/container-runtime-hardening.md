# Endurecimiento del runtime de contenedores

El MVP endurece únicamente el backend. PostgreSQL conserva su configuración, sus volúmenes y sus rutas operativas actuales; el filesystem de solo lectura también queda diferido.

## Política aplicada

Los cuatro slots backend de `infra/deploy/compose.yml` y el contenedor efímero que ejecuta migraciones aplican:

- usuario no privilegiado `bun` definido por el Dockerfile;
- `no-new-privileges:true`;
- eliminación de todas las capacidades Linux mediante `cap_drop: ALL`;
- límite predeterminado de `1.0` CPU y `768m` de memoria;
- ningún socket, volumen del host ni nueva ruta de secretos montada en el backend.

Los valores se midieron el 16 de julio de 2026 contra el VPS actual mediante consultas no mutantes: 4 vCPU, 8.25 GB de RAM y aproximadamente 50–55 MiB por cada backend activo. El límite de 768 MiB deja más de diez veces el uso estable observado y permite mantener desarrollo, producción y un slot transitorio durante el cambio blue/green sin reservar toda la capacidad del host.

Los límites pueden ajustarse en `/srv/cal-tracker/env/deploy.env` sin reconstruir la imagen:

```dotenv
BACKEND_CPU_LIMIT=1.0
BACKEND_MEMORY_LIMIT=768m
```

El despliegue rechaza valores de CPU no positivos y formatos de memoria distintos de los aceptados explícitamente. Si las variables aún no existen en un servidor aprovisionado, se usan los valores predeterminados anteriores.

## Validación

La comprobación rápida y no mutante renderiza el Compose y verifica los cuatro backends, el contenedor de migraciones, el usuario de la imagen, la ausencia de mounts y que PostgreSQL no reciba el hardening diferido:

```bash
scripts/deploy/test-container-runtime-policy.sh
```

Para validar una imagen backend construida localmente:

```bash
docker build -f apps/backend/Dockerfile -t bettercalories-backend:runtime-hardening .
scripts/deploy/smoke-container-runtime-hardening.sh bettercalories-backend:runtime-hardening
```

El smoke usa una red y una base de datos efímeras. Ejecuta migraciones, comprueba el healthcheck, UID, `NoNewPrivs`, capacidades efectivas y que `setuid(0)` falle. Después fuerza un OOM en un contenedor auxiliar limitado a 128 MiB y demuestra que PostgreSQL y el backend siguen sanos. Finalmente realiza `pg_dump` y `pg_restore` en la base efímera.

## Despliegue y reversión

El cambio entra por la metodología existente: push a `develop` para desarrollo y tag `v*` para producción. Primero valida desarrollo y observa durante un ciclo normal:

```bash
docker stats --no-stream \
  cal-tracker-backend-dev-blue cal-tracker-backend-dev-green \
  cal-tracker-backend-pro-blue cal-tracker-backend-pro-green
docker inspect cal-tracker-backend-dev-blue \
  --format '{{json .HostConfig.SecurityOpt}} {{json .HostConfig.CapDrop}} {{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}'
```

Si una carga legítima alcanza el límite, ajusta solo `BACKEND_CPU_LIMIT` o `BACKEND_MEMORY_LIMIT` en el secreto `DEPLOY_ENV` del entorno y repite el despliegue. No retires `no-new-privileges` ni restaures capacidades como respuesta a presión de recursos. Los logs continúan en el driver estándar de Docker y los healthchecks, migraciones, backups y restauraciones conservan sus rutas actuales.
