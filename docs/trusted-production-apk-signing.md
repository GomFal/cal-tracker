# Firma de confianza de los APK de producción

Los APK `prod` conservan el canal de publicación directa del MVP, pero solo se
publican si están firmados por la identidad release aprobada. No existe una
excepción para firmarlos con la clave Android Debug. Los APK `devRelease` usan
una clave de desarrollo estable y separada; las builds `devDebug` y `local` no
necesitan acceso a ninguna clave de publicación.

## Contrato ejecutable

La protección se aplica en tres niveles:

1. Gradle vincula `prodRelease` únicamente a la configuración `release` y
   `devRelease` a su configuración estable `devRelease`. Una invocación directa
   se detiene si falta la identidad requerida para su canal.
2. `scripts/mobile/build-android.sh` exige el keystore y el fingerprint SHA-256
   aprobado para el canal solicitado antes de construir. Después valida la
   firma del APK con `apksigner` antes de copiarlo a `dist/`.
3. El workflow manual reconstruye el keystore aislado del canal en el
   directorio temporal del runner, vuelve a verificar el APK antes de subir el
   artefacto y elimina el material temporal incluso si la build falla. La ruta
   que publica un APK ya construido repite la verificación antes de enviarlo al
   servidor.

La verificación rechaza una firma inválida, un certificado cuyo fingerprint no
coincida, varios firmantes actuales y cualquier certificado con identidad
`CN=Android Debug`.

## Secretos del entorno protegido

Configura estos secretos exclusivamente en el GitHub Environment `production`:

| Secreto | Contenido |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Keystore release completo codificado en base64 en una sola línea. |
| `ANDROID_RELEASE_STORE_PASSWORD` | Contraseña del keystore. |
| `ANDROID_RELEASE_KEY_ALIAS` | Alias nominal de la clave release. |
| `ANDROID_RELEASE_KEY_PASSWORD` | Contraseña de la clave privada. |
| `ANDROID_RELEASE_CERT_SHA256` | SHA-256 del certificado público aprobado; se admiten hexadecimales con o sin `:`. |

El Environment `production` debe mantener las aprobaciones y custodios
nominales que utilice el proyecto. No copies estos secretos al entorno
`development`, a variables del repositorio, ficheros `.env`, logs o artefactos.
Base64 solo transporta el keystore: no constituye cifrado.

## Generación inicial

La generación se hace fuera del repositorio, en una estación controlada, y no
durante una ejecución CI:

```bash
umask 077
keytool -genkeypair \
  -keystore bettercalories-release.jks \
  -storetype PKCS12 \
  -alias bettercalories-release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -dname "CN=BetterCalories,O=BetterCalories,C=ES"

keytool -list -v \
  -keystore bettercalories-release.jks \
  -alias bettercalories-release

base64 -w 0 bettercalories-release.jks
```

Dos personas deben contrastar el SHA-256 mostrado por `keytool` antes de
registrarlo como fingerprint aprobado. El texto base64 se introduce
directamente como secreto y no se guarda en el repositorio ni en un historial
de terminal compartido.

## Custodia y recuperación

- Mantén al menos dos copias offline cifradas del keystore en ubicaciones
  separadas. Cifra cada soporte antes de sacarlo de la estación controlada.
- Guarda las contraseñas en el gestor de secretos operativo, separado de las
  copias del keystore. Registra custodios nominales y acceso de emergencia fuera
  del repositorio.
- Cada trimestre, o antes de una publicación relevante, recupera una copia en
  un directorio temporal con permisos `0700`, ejecuta `keytool -list` y compara
  el fingerprint con `ANDROID_RELEASE_CERT_SHA256`. El ejercicio no necesita
  publicar nada.
- Después del ejercicio, elimina la copia temporal y registra fecha, custodios
  y resultado sin registrar contraseñas, clave, base64 ni contenido del
  keystore.

Si se pierde el secreto de GitHub pero la clave no está comprometida, restaura
el mismo keystore desde la copia offline, contrasta el fingerprint y reemplaza
los cinco secretos del Environment. Ejecuta el workflow primero contra una
revisión controlada y confirma que la fase de verificación pasa antes de
autorizar una publicación.

## Rotación o compromiso

Una actualización Android instalada directamente debe conservar una identidad
de firma compatible. Por eso no se sustituye el keystore de forma inmediata ni
se cambia solo el secreto de fingerprint.

1. Detén las publicaciones y conserva la clave anterior offline.
2. Genera la nueva clave en una estación controlada.
3. Prepara y revisa una prueba de rotación de firma compatible con las versiones
   Android soportadas, incluyendo el linaje de firma cuando corresponda.
4. Instala primero un APK publicado con la clave anterior y verifica en un
   dispositivo que Android acepta la actualización firmada con el material
   rotado.
5. En un único cambio operativo, sustituye keystore, alias, contraseñas y
   fingerprint aprobado en el Environment `production`.
6. Publica solo después de repetir `apksigner verify --verbose --print-certs` y
   de contrastar el fingerprint. Si la actualización de prueba falla, restaura
   los secretos anteriores y no publiques.

La rotación no elimina la copia cifrada de la clave anterior mientras existan
instalaciones que dependan de ella. Una migración futura a Play App Signing se
documentará por separado.

## Validación local de política

```bash
scripts/deploy/test-apk-signing-policy.sh
```

La prueba cubre ausencia y configuración parcial de clave, intento de habilitar
firma debug, fingerprint ausente o distinto, certificado Android Debug, firma
inválida, limpieza del runner y enlace estructural de Gradle/CI. Cuando
`keytool`, `jar` y `apksigner` están disponibles también genera un keystore
efímero, firma un APK de prueba y verifica el certificado real; todo se elimina
al finalizar.
