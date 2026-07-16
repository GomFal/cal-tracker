# Controles mínimos de cadena de suministro

El MVP fija las entradas que afectan directamente a las builds y al runtime sin
añadir infraestructura de gobierno. La versión canónica de Bun es `1.3.13` en
`.mise.toml`; `package.json`, los workflows de backend y las dos etapas del
Dockerfile deben coincidir con ella.

Las bases revisadas son:

- `oven/bun:1.3.13` para construir y ejecutar el backend;
- `pgvector/pgvector:0.8.2-pg16-bookworm` para PostgreSQL 16 con pgvector, tanto
  en el despliegue como en el entorno local y el smoke test de runtime.

Los tags operativos del backend (`dev-*`, `pro-*` y `*-latest`) no son imágenes
base. El despliegue sigue consumiendo por digest OCI según
`trusted-production-deployments.md`. Tampoco forman parte de esta política
`runs-on: ubuntu-latest`, el manifest móvil `latest.json` ni los tags mayores de
GitHub Actions, que se mantienen durante el MVP.

## Instalación reproducible

- CI y Docker usan `bun install --frozen-lockfile` con el `bun.lock` versionado.
- La tarea genérica de mise usa `bun install --frozen-lockfile`; `bun.lock` es la
  resolución canónica de los workspaces JavaScript.
- Las builds Flutter usan `flutter pub get --enforce-lockfile` con
  `apps/mobile/pubspec.lock`.

Ejecuta la política localmente con:

```bash
scripts/deploy/test-supply-chain-policy.sh
```

El validador inspecciona únicamente las superficies declaradas de build y
producción. Un texto histórico, `latest.json` o una imagen local fuera de esas
superficies no bloquea una corrección urgente por coincidencia textual.

## Actualización

Actualiza Bun y las imágenes en una revisión normal. Para Bun, cambia primero
`.mise.toml` y alinea `package.json`, CI y Dockerfile en el mismo cambio. Para
una base, comprueba que el tag exista, revisa las notas del proveedor y ejecuta
la política, las pruebas del backend y la validación móvil proporcional. Si el
tag ha sido retirado, la build debe fallar; no se sustituye por `latest` como
atajo.

SBOM, attestations, firma de contenedores, escáneres adicionales y pin por commit
de GitHub Actions quedan explícitamente fuera del MVP.
