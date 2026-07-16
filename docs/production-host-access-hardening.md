# Endurecimiento del acceso al VPS de producción

Este procedimiento migra la administración del VPS desde `root` con contraseña a un usuario nominal con clave y `sudo`. SSH continúa siendo público durante el MVP. La aplicación está dividida en fases para no retirar el acceso anterior antes de demostrar una alternativa y confirmar la consola de recuperación del proveedor.

El script no se ejecuta desde CI y no debe incorporarse a un despliegue automático. Una persona con acceso actual al host debe completar la migración en una ventana operativa, manteniendo abiertas las sesiones existentes hasta terminar las comprobaciones.

## Preparación local

Genera o selecciona una clave Ed25519 exclusiva para administración. No copies la clave privada al repositorio ni al servidor. Copia al host este directorio y la clave pública:

```bash
scp -r infra/security root@bettercalories.app:/root/bettercalories-security
scp ~/.ssh/bettercalories-production.pub root@bettercalories.app:/root/bettercalories-production.pub
```

Antes de cualquier cambio, inicia sesión en el panel del proveedor y comprueba que puedes abrir la consola del VPS. No basta con conocer la contraseña del panel: la consola debe estar disponible para este servidor.

## 1. Preparar el usuario sin cambiar SSH

Desde la sesión administrativa existente, elige el nombre nominal real del operador; `operator` es solo un ejemplo:

```bash
cd /root/bettercalories-security
sudo ./harden-production-access.sh prepare \
  --operator operator \
  --public-key-file /root/bettercalories-production.pub
```

Esta fase instala las dependencias, crea o actualiza la cuenta, sustituye su `authorized_keys`, configura elevación trazable mediante `sudo` y deja las políticas en un área de staging. No modifica la política SSH activa, UFW ni fail2ban.

## 2. Demostrar la ruta alternativa

Mantén abierta la sesión anterior. Desde otra terminal, fuerza autenticación exclusiva mediante clave:

```bash
ssh \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o PreferredAuthentications=publickey \
  -i ~/.ssh/bettercalories-production \
  operator@bettercalories.app
```

En esa nueva sesión ejecuta inmediatamente:

```bash
cd /root/bettercalories-security
sudo --preserve-env=SSH_CONNECTION ./harden-production-access.sh verify \
  --operator operator \
  --recovery-console-confirmed
```

La verificación exige que el comando llegue mediante `sudo` desde la cuenta indicada, que exista una sesión SSH, que el journal registre recientemente `Accepted publickey`, que coincida el fingerprint instalado y que se haya confirmado explícitamente la consola del proveedor. La prueba caduca en una hora.

## 3. Aplicar el endurecimiento

Solo después de completar las dos fases anteriores:

```bash
sudo ./harden-production-access.sh enforce \
  --operator operator \
  --confirm DISABLE_ROOT_AND_PASSWORD
```

El script valida la sintaxis y la configuración efectiva antes de recargar SSH. Si esa validación o la recarga fallan, restaura automáticamente el drop-in anterior. A continuación:

- deshabilita contraseñas, keyboard-interactive y login directo de `root`;
- exige clave pública para SSH;
- activa fail2ban para SSH con bloqueo incremental;
- reinicia UFW con política entrante denegada y permite únicamente TCP 22, 80 y 443;
- conserva eventos operativos en el journal con el identificador `bettercalories-access`.

El reinicio intencionado de UFW elimina reglas anteriores. Antes de ejecutar confirma que el host no publica otro servicio necesario. Los puertos internos de Docker deben continuar enlazados a loopback o a redes internas.

## 4. Validación posterior

Mantén abiertas las sesiones existentes y abre una tercera sesión nominal. Comprueba el estado:

```bash
sudo ./harden-production-access.sh status --operator operator
```

Desde un terminal separado verifica los rechazos sin realizar intentos repetidos innecesarios:

```bash
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password root@bettercalories.app
ssh -o PasswordAuthentication=no -i ~/.ssh/bettercalories-production root@bettercalories.app
```

Ambos deben fallar. La cuenta nominal debe entrar con clave y `sudo -n true` debe finalizar correctamente. `status` debe mostrar UFW activo, únicamente 22/80/443, y el jail `sshd` activo. Las decisiones de un proveedor externo de red o firewall deben reflejar la misma lista.

Antes de deshabilitar `root`, completa la migración del usuario de despliegue descrita en [trusted-production-deployments.md](trusted-production-deployments.md). Ejecuta al menos un despliegue de desarrollo con `VPS_USER=bettercalories-deploy` y confirma su registro remoto. Si GitHub Actions todavía usa `VPS_USER=root`, no ejecutes la fase `enforce`.

## Recuperación básica

Si se pierde la última clave válida, entra desde la consola del proveedor y ejecuta:

```bash
cd /root/bettercalories-security
sudo ./harden-production-access.sh rollback-ssh --console-recovery-confirmed
```

Esto restaura el drop-in SSH previo y mantiene TCP/22 permitido en UFW. Después corrige o rota la clave y repite todas las fases. La custodia formal, copias de emergencia y simulacros periódicos quedan diferidos hasta después de validar el MVP.
