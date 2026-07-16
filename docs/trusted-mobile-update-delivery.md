# Entrega confiable de actualizaciones móviles

El actualizador directo de Android es un mecanismo temporal del MVP. Se
eliminará cuando Play Store sea el canal de distribución. Mientras exista, la
app solo confía en dos contratos exactos:

| Canal | Package ID | Origen del manifest y del APK |
| --- | --- | --- |
| `dev` | `app.bettercalories.dev` | `https://dev-api.bettercalories.app` |
| `prod` | `app.bettercalories` | `https://api.bettercalories.app` |

No se admiten puertos explícitos, credenciales, query strings, fragments,
otros esquemas ni otros hosts. El manifest vive en `/apk/latest.json` y el APK
debe ser un fichero `.apk` directo bajo `/apk/`.

## Contrato del manifest

Los campos obligatorios son `channel`, `packageName`, `versionName`,
`versionCode`, `apkUrl` y `publishedAt`. `sha256` y `sizeBytes` continúan siendo
metadatos de publicación: la app no descarga el APK ni calcula su hash. Los
campos futuros desconocidos se toleran para poder ampliar el documento, pero
los campos conocidos se validan con tipos estrictos.

La app compara el package instalado con el canal derivado de su API oficial y
solo ofrece un `versionCode` estrictamente superior. Un manifest igual o
inferior no produce un prompt y tampoco puede abrirse mediante el servicio. Un
canal, package, origen o formato incompatible bloquea la actualización con un
mensaje seguro que no muestra URLs ni detalles internos.

El GET del manifest y el HEAD previo del APK desactivan redirects. El HEAD no
descarga el artefacto: confirma que el endpoint directo responde antes de
delegar la descarga al navegador externo. No existe una verificación
criptográfica propia del manifest ni una descarga interna en este MVP.

## Publicación

`scripts/mobile/deploy-server-apks.sh` comprueba con `apkanalyzer` que el
package y el `versionCode` reales del APK coinciden con el canal, genera esos
campos, valida el JSON antes de subirlo y vuelve a validar el documento público.
La publicación usa orígenes constantes, rechaza redirects y no permite volver
a publicar el mismo `versionCode` ni uno inferior. Para publicar:

1. incrementa el build number de `apps/mobile/pubspec.yaml`;
2. construye y verifica el APK del flavor;
3. ejecuta el workflow manual `Mobile APK Deploy`;
4. comprueba que el manifest y el APK público superan la validación sin
   redirects.

La identidad del editor no se infiere del JSON. Para `prod`, el contrato de
esta feature depende del pipeline de firma release: el APK debe haber superado
`scripts/mobile/verify-apk-signing.sh` contra `ANDROID_RELEASE_CERT_SHA256`
antes de llegar a `deploy-server-apks.sh`. Android solo acepta una actualización
del package instalado cuando su identidad de firma es compatible. No se debe
añadir el fingerprint al manifest como si eso demostrara por sí mismo la firma
del binario.

## Límite del navegador

El HEAD sin redirects elimina redirects estables o configurados en el endpoint
al comprobarlo. Como la descarga posterior pertenece a otro proceso, existe
una ventana TOCTOU entre el HEAD y la petición del navegador. En el alcance
MVP, el riesgo residual queda limitado por TLS, el origen exacto y la
verificación de package/firma que Android aplica durante la instalación. La
eliminación definitiva del flujo llega con Play Store.
