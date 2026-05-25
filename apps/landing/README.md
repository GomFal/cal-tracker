# Better Calories Landing

Sitio estático de marketing para `https://bettercalories.app`.

## Validar

```bash
bun run landing:validate
```

## Ver en local

```bash
bun run landing:serve
```

Después abre `http://localhost:4173`.

## Publicar

Despliega la landing y la configuración NGINX canónica con:

```bash
bun run landing:deploy
```

El script valida la landing, empaqueta los archivos públicos, crea un backup
del webroot actual y publica en:

```text
/var/www/bettercalories.app/html
```

También instala la configuración versionada de `bettercalories.app` para que
`www.bettercalories.app` redirija a `https://bettercalories.app`.

Variables útiles:

```text
BETTERCALORIES_LANDING_SSH_HOST=root@bettercalories.app
BETTERCALORIES_LANDING_REMOTE_ROOT=/var/www/bettercalories.app/html
BETTERCALORIES_LANDING_STATE_DIR=/srv/cal-tracker/landing
```

Los backups remotos quedan en:

```text
/srv/cal-tracker/landing/backups/<timestamp>
```

La landing enlaza la beta Android en:

```text
https://api.bettercalories.app/apk/latest.apk
```

Ese alias se crea al publicar APKs con `scripts/mobile/deploy-server-apks.sh`.
