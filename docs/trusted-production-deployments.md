# Despliegues de producción verificables

El flujo mantiene la promoción actual: `develop` despliega desarrollo, los tags `v*` despliegan producción y el APK se publica mediante el workflow manual existente. No se añaden aprobación manual ni firma de tags durante el MVP.

La migración sí cambia dos relaciones de confianza: GitHub Actions deja de aprender la clave del host durante cada job y deja de iniciar sesión como `root`. Los workflows fallan de forma explícita si `VPS_USER=root`, si falta el host en `known_hosts`, si cambia su clave o si los fingerprints protegidos no coinciden.

## Secretos de GitHub por entorno

Configura estos secretos tanto en `development` como en `production`:

- `VPS_HOST`: solo el hostname, por ejemplo `bettercalories.app`.
- `VPS_USER`: la cuenta dedicada, por defecto `bettercalories-deploy`.
- `VPS_SSH_PRIVATE_KEY`: clave privada exclusiva de CI.
- `VPS_SSH_KNOWN_HOSTS`: una o más líneas `known_hosts` obtenidas por un canal administrativo verificado.
- `VPS_SSH_HOST_KEY_FINGERPRINTS`: los fingerprints `SHA256:...` exactos de esas líneas, separados por saltos de línea.

No obtengas estos valores con `ssh-keyscan` desde el runner. Desde la consola del proveedor o una sesión cuya identidad ya esté verificada, un administrador puede consultar las claves activas con:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

Construye la línea `known_hosts` anteponiendo `bettercalories.app` al tipo y contenido de la clave pública. Compara el fingerprint desde un segundo canal antes de guardar ambos secretos. El helper `scripts/deploy/configure-ssh.sh` compara el conjunto exacto sin imprimir claves ni fingerprints y crea una configuración con `StrictHostKeyChecking=yes`, autenticación no interactiva y contraseña deshabilitada.

## Aprovisionamiento fail-safe

Este paso no se ejecuta desde CI. Usa una clave Ed25519 exclusiva para GitHub Actions y conserva abierta la sesión administrativa actual:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/bettercalories-deploy-ci -C bettercalories-deploy-ci
scp -r infra/deploy operator@bettercalories.app:/tmp/bettercalories-deploy
scp ~/.ssh/bettercalories-deploy-ci.pub operator@bettercalories.app:/tmp/bettercalories-deploy-ci.pub
ssh operator@bettercalories.app
sudo /tmp/bettercalories-deploy/provision-deploy-user.sh \
  --public-key-file /tmp/bettercalories-deploy-ci.pub
```

El aprovisionamiento:

- crea una cuenta sin contraseña, deja su clave autorizada bajo propiedad de `root` y limita forwarding, PTY y scripts SSH de usuario;
- concede mediante `sudoers` únicamente `/usr/local/sbin/bettercalories-deploy`;
- instala el dispatcher y scripts de infraestructura como `root`;
- crea un staging privado y conserva los directorios publicados bajo control privilegiado;
- no modifica `sshd`, UFW ni la cuenta administrativa.

Los workflows rutinarios no pueden sustituir el dispatcher ni los scripts que este ejecuta con privilegios. Una modificación futura de `infra/deploy/` requiere repetir este aprovisionamiento de forma administrativa y revisada; el despliegue de código de aplicación continúa automático.

Antes de endurecer SSH:

1. configura los cinco secretos de desarrollo;
2. ejecuta un push a `develop` y comprueba el despliegue;
3. configura los mismos secretos de producción;
4. ejecuta el workflow móvil para `dev` y comprueba su manifest;
5. confirma que `/srv/cal-tracker/state/deployments.jsonl` contiene commit, digest o checksum, run y actor;
6. solo entonces ejecuta la fase `enforce` de `production-host-access-hardening.md`.

Si falla cualquier validación, no cambies la política SSH. Corrige la cuenta, la clave o los secretos mientras la sesión administrativa anterior sigue abierta.

## Procedencia y promoción

El backend etiqueta las imágenes para operación, pero despliega la referencia inmutable `ghcr.io/autofactu/cal-tracker-backend@sha256:...` producida por el mismo job. La imagen contiene la etiqueta OCI `org.opencontainers.image.revision`. La política de promoción continúa expresada por el trigger `v*`; un tag que no coincida con ese patrón no inicia el despliegue de producción.

Los manifests APK incluyen SHA-256, commit fuente, run y actor. El dispatcher recalcula el SHA-256 antes de publicar. Backend, APK y landing añaden una entrada al log remoto propiedad de `root` después de completar el cambio. GitHub Actions también deja commit, artefacto y actor en el resumen del job.

El `actor` es quien inicia el evento o workflow; no representa una aprobación manual adicional. Las reglas de aprobación de environments, tags firmados, attestations y un registro externo quedan fuera del MVP.

## Rotación de claves

Para rotar la clave SSH de CI, vuelve a ejecutar el aprovisionamiento con la nueva clave pública y, antes de cerrar la sesión administrativa, actualiza `VPS_SSH_PRIVATE_KEY` y valida desarrollo.

Para rotar una clave de host sin TOFU:

1. instala la nueva clave manteniendo activa la anterior;
2. verifica por consola sus fingerprints;
3. añade líneas y fingerprints nuevos a ambos secretos;
4. valida desarrollo;
5. retira la clave antigua del servidor;
6. elimina sus líneas y fingerprints de los secretos y vuelve a validar.

Una clave inesperada siempre bloquea el job. No la reemplaces basándote únicamente en el error del workflow.
