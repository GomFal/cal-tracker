# Endurecimiento del acceso al VPS de producción

Este procedimiento migra la administración del VPS desde acceso SSH directo
como `root`, incluida la autenticación por contraseña, a una cuenta nominal con
clave pública y `sudo`. También activa fail2ban y establece una política UFW
explícita para los puertos públicos del MVP.

SSH continúa expuesto públicamente durante esta fase. Tailscale, la custodia
formal de claves de emergencia y los simulacros periódicos de recuperación se
mantienen fuera del alcance del MVP.

El cambio es manual y no se ejecuta desde CI. Debe realizarlo una persona con
acceso administrativo actual, en una ventana operativa y manteniendo abiertas
las sesiones anteriores hasta completar todas las comprobaciones.

## Resultado esperado

Al finalizar correctamente:

- solo se puede autenticar por SSH mediante clave pública;
- `root` no puede iniciar una sesión SSH, ni siquiera con una clave válida;
- una cuenta nominal puede entrar con su propia clave y elevar mediante `sudo`;
- la cuenta automatizada `bettercalories-deploy` continúa desplegando mediante
  su clave y dispatcher restringido;
- fail2ban protege SSH con bloqueos incrementales;
- UFW deniega por defecto el tráfico entrante y permite únicamente TCP 22, 80 y
  443.

El procedimiento no bloquea la contraseña local de `root`: deshabilita su
acceso por SSH. Esto permite conservar la vía de recuperación que proporcione la
consola del proveedor.

## Condiciones obligatorias antes de empezar

No ejecutes la fase `enforce` hasta cumplir todas estas condiciones:

1. Has abierto realmente la consola web, KVM o VNC del VPS desde el panel del
   proveedor y has comprobado que permite acceder al servidor. Ver el botón de
   consola no es una comprobación suficiente.
2. Mantienes abierta la sesión SSH administrativa existente.
3. La cuenta `bettercalories-deploy` ya está aprovisionada, los secretos SSH de
   GitHub usan esa cuenta y al menos un despliegue de desarrollo ha terminado
   correctamente. Consulta
   [trusted-production-deployments.md](trusted-production-deployments.md).
4. El servidor no necesita exponer ningún puerto distinto de TCP 22, 80 y 443.
5. La clave privada administrativa está almacenada únicamente en el equipo del
   operador y protegida con una passphrase.

Si una condición no se cumple, detén el procedimiento y corrígela mientras el
acceso anterior siga disponible.

## 1. Auditar los puertos antes de reiniciar UFW

Desde la sesión administrativa existente, inspecciona los listeners, los
puertos publicados por Docker y las reglas actuales:

```bash
sudo ss -lntup
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}'
sudo ufw status numbered
```

La fase `enforce` ejecuta `ufw --force reset`; por tanto elimina las reglas UFW
anteriores y permite solamente:

- `22/tcp`, para SSH mediante clave;
- `80/tcp`, para redirecciones HTTP y ACME;
- `443/tcp`, para HTTPS.

No continúes si otro servicio debe ser accesible desde Internet. Los puertos de
PostgreSQL, backend interno y servicios auxiliares deben estar enlazados a
loopback o limitados a redes internas. Comprueba también la política de firewall
del proveedor y haz que refleje la misma lista de puertos.

## 2. Crear una clave administrativa nominal

En el equipo del operador, no en el VPS, genera una clave Ed25519 exclusiva:

```bash
ssh-keygen \
  -t ed25519 \
  -a 100 \
  -f ~/.ssh/bettercalories-production-admin \
  -C "nominal-operator-bettercalories-production"
```

Introduce una passphrase cuando `ssh-keygen` la solicite. Los archivos creados
son:

```text
~/.ssh/bettercalories-production-admin      # clave privada
~/.ssh/bettercalories-production-admin.pub  # clave pública
```

No copies la clave privada al servidor ni al repositorio. Puedes revisar el
fingerprint antes de continuar:

```bash
ssh-keygen -lf ~/.ssh/bettercalories-production-admin.pub
```

## 3. Copiar el procedimiento y la clave pública

Desde la raíz de este repositorio:

```bash
scp -r \
  infra/security \
  root@bettercalories.app:/root/bettercalories-security

scp \
  ~/.ssh/bettercalories-production-admin.pub \
  root@bettercalories.app:/root/bettercalories-production-admin.pub
```

Solo el directorio del procedimiento y la clave pública deben llegar al VPS.

## 4. Preparar la cuenta sin cambiar la política SSH

Elige el nombre nominal real del operador. En los ejemplos se utiliza
`antonio`; sustitúyelo de forma consistente si corresponde otro nombre.

Desde la sesión administrativa existente:

```bash
cd /root/bettercalories-security
chmod +x harden-production-access.sh

sudo ./harden-production-access.sh prepare \
  --operator antonio \
  --public-key-file /root/bettercalories-production-admin.pub
```

Esta fase:

- instala OpenSSH Server, sudo, fail2ban y UFW;
- crea o actualiza la cuenta nominal;
- sustituye su `authorized_keys` por la única clave pública indicada;
- habilita elevación no interactiva mediante `sudo`;
- prepara las políticas SSH y fail2ban en un directorio de staging.

Todavía no modifica la política SSH activa, UFW ni fail2ban. La salida debe
confirmar explícitamente:

```text
Prepared nominal operator 'antonio'; SSH policy has NOT been changed.
```

## 5. Demostrar la ruta de acceso alternativa

Mantén abierta la sesión administrativa anterior. Desde una segunda terminal
del equipo del operador, fuerza autenticación exclusiva mediante la nueva clave:

```bash
ssh \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o PreferredAuthentications=publickey \
  -o IdentitiesOnly=yes \
  -i ~/.ssh/bettercalories-production-admin \
  antonio@bettercalories.app
```

En la nueva sesión comprueba la identidad, el host y `sudo`:

```bash
whoami
hostname
sudo -n true
```

Los resultados esperados son `antonio`, el hostname del VPS y código de salida
cero para `sudo -n true`. Si cualquiera falla, no ejecutes `verify` ni
`enforce`.

## 6. Registrar la verificación

Solo después de haber probado la consola del proveedor, ejecuta desde la sesión
nominal:

```bash
sudo --preserve-env=SSH_CONNECTION \
  /root/bettercalories-security/harden-production-access.sh verify \
  --operator antonio \
  --recovery-console-confirmed
```

Se usa la ruta absoluta porque una cuenta nominal normalmente no puede hacer
`cd /root` antes de elevar permisos. `--preserve-env=SSH_CONNECTION` permite que
el script demuestre que la orden procede de la sesión SSH nominal que acaba de
autenticarse mediante clave.

La verificación exige:

- que `sudo` haya sido invocado por la cuenta indicada y no directamente por
  `root`;
- que exista una sesión SSH real;
- que el journal registre recientemente `Accepted publickey` desde la misma IP;
- que el fingerprint instalado coincida con la clave preparada;
- que `sudo` no interactivo y la sintaxis de `sshd` funcionen;
- que se confirme explícitamente la consola del proveedor.

La prueba caduca una hora después. Si caduca, repite el acceso nominal y esta
fase antes de continuar.

## 7. Aplicar el endurecimiento

Mantén abiertas las dos sesiones anteriores y ejecuta desde la sesión nominal:

```bash
sudo /root/bettercalories-security/harden-production-access.sh enforce \
  --operator antonio \
  --confirm DISABLE_ROOT_AND_PASSWORD
```

El script valida la sintaxis y la configuración efectiva antes y después de
recargar SSH. Si la validación o la recarga fallan antes de confirmar el cambio,
restaura automáticamente el drop-in anterior.

La política resultante:

- habilita autenticación por clave pública;
- deshabilita contraseñas y keyboard-interactive;
- exige `AuthenticationMethods publickey`;
- deshabilita el acceso SSH directo de `root`;
- limita los intentos y el tiempo de login;
- activa fail2ban para SSH con bloqueo incremental;
- reinicia UFW, deniega tráfico entrante y permite TCP 22, 80 y 443;
- conserva eventos operativos en el journal con el identificador
  `bettercalories-access`.

## 8. Validar desde una tercera sesión

No cierres ninguna sesión anterior. Abre una tercera sesión nominal desde el
equipo del operador:

```bash
ssh \
  -o PasswordAuthentication=no \
  -o IdentitiesOnly=yes \
  -i ~/.ssh/bettercalories-production-admin \
  antonio@bettercalories.app
```

Dentro del VPS consulta el estado completo:

```bash
sudo /root/bettercalories-security/harden-production-access.sh status \
  --operator antonio
```

Debe mostrar, como mínimo:

```text
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
authenticationmethods publickey
permitrootlogin no
```

UFW debe estar activo con únicamente 22, 80 y 443, y el jail `sshd` de fail2ban
debe estar activo. Comprueba también que la aplicación continúa respondiendo:

```bash
curl -fsS https://dev-api.bettercalories.app/v1/health
curl -fsS https://api.bettercalories.app/v1/health
```

La respuesta esperada en ambos entornos es:

```json
{"ok":true,"service":"cal-tracker-backend"}
```

Finalmente, vuelve a ejecutar un despliegue de desarrollo desde GitHub Actions
y confirma que `bettercalories-deploy` continúa funcionando y que se añade un
nuevo registro a `/srv/cal-tracker/state/deployments.jsonl`.

## 9. Confirmar el rechazo de `root`

Desde el equipo del operador, realiza una sola vez cada prueba:

```bash
ssh \
  -o BatchMode=yes \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  root@bettercalories.app true
```

```bash
ssh \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o IdentitiesOnly=yes \
  -i ~/.ssh/bettercalories-production-admin \
  root@bettercalories.app true
```

Ambas deben fallar con `Permission denied`. No repitas innecesariamente los
intentos: fail2ban contabiliza los rechazos y puede bloquear temporalmente la IP
del operador.

Solo después de superar todas las validaciones puedes cerrar la sesión root
anterior. Conserva al menos una sesión nominal funcional hasta comprobar el
despliegue de desarrollo posterior.

## Recuperación por consola

Si se pierde el último acceso SSH válido, entra mediante la consola del
proveedor y ejecuta:

```bash
cd /root/bettercalories-security

sudo ./harden-production-access.sh rollback-ssh \
  --console-recovery-confirmed
```

Esto restaura el drop-in SSH previo y mantiene TCP/22 permitido en UFW. No
restaura las reglas UFW anteriores ni desactiva fail2ban. Después revisa el
estado:

```bash
sudo sshd -t
sudo ufw status verbose
sudo fail2ban-client status sshd
```

Corrige o rota la clave administrativa y repite todas las fases desde
`prepare`. No vuelvas a ejecutar `enforce` basándote únicamente en una sesión
SSH antigua que haya permanecido abierta.

## Criterio de finalización

La migración solo se considera terminada cuando:

- una conexión nominal completamente nueva funciona mediante clave;
- `sudo -n true` funciona desde esa cuenta;
- los accesos SSH de `root` por contraseña y por clave fallan;
- `status` confirma la política SSH, UFW y fail2ban;
- los health checks de desarrollo y producción responden;
- un despliegue de desarrollo posterior completa mediante
  `bettercalories-deploy`;
- la consola del proveedor continúa disponible como vía de recuperación.
