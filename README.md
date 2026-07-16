# Cal Tracker

Aplicacion para registrar y consultar informacion nutricional.

## Landing y servidor

Dominio: `https://bettercalories.app`

IP del servidor: `82.223.104.126`

El acceso administrativo objetivo usa una cuenta nominal, clave pública y elevación mediante `sudo`; no se deben documentar usuarios o claves privadas compartidos. La migración segura y sus comprobaciones están descritas en [docs/production-host-access-hardening.md](docs/production-host-access-hardening.md). Hasta aplicar ese procedimiento, comprueba el estado real del host y no cierres la vía existente.

El servidor esta preparado con Docker, NGINX y HTTPS mediante Let's Encrypt.
La landing estatica del producto vive en `apps/landing` y esta preparada para
publicarse en `/var/www/bettercalories.app/html`.

## CI/CD backend

El backend se despliega con GitHub Actions, Bun, GHCR y blue/green en Docker.

Dominios API:

- Dev: `https://dev-api.bettercalories.app`
- Pro: `https://api.bettercalories.app`

Registros DNS necesarios:

```text
A api.bettercalories.app -> 82.223.104.126
A dev-api.bettercalories.app -> 82.223.104.126
```

Secrets de GitHub necesarios:

- `VPS_HOST`: `82.223.104.126`
- `VPS_USER`: usuario remoto definido por el flujo de despliegue vigente
- `VPS_SSH_PRIVATE_KEY`
- `GHCR_USERNAME`
- `GHCR_READ_TOKEN`
- `DEPLOY_ENV_FILE`
- `DEV_ENV_FILE`
- `PRO_ENV_FILE`

`DEPLOY_ENV_FILE` debe incluir:

```env
POSTGRES_PASSWORD=change-me
BACKEND_IMAGE=ghcr.io/autofactu/cal-tracker-backend:bootstrap
```

Dev usa el schema Postgres `cal_tracker_dev` y produccion usa `cal_tracker_pro`.
El despliegue a dev se ejecuta con push a `develop`; produccion se ejecuta con tags `v*`.
