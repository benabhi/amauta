# ADR-0002 · Entorno de desarrollo con Docker Compose

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RNF-DEV-001 a RNF-DEV-006, RNF-DEV-008, RNF-DEV-010, RNF-DEV-012, DEC-035 |

## Contexto

El entorno principal de desarrollo es Windows con Docker Desktop y el repositorio en el disco de Windows (DEC-035). No hay Elixir instalado en el host: todo corre en contenedores. Los eventos de cambio de archivos no cruzan de forma confiable el montaje desde `C:\`.

## Decisión

- **Servicios** (`compose.yaml`): `app` (Phoenix), `db` (PostgreSQL 18.6), `storage` (Garage 2.4.1), `storage-init` (tarea única) y `mail` (Mailpit 1.31.4). Los servicios opcionales del ERS (ClamAV, PDF, Livebook) se agregan cuando haga falta.
- **Imagen de desarrollo** (`docker/dev/Dockerfile`): `hexpm/elixir` 1.20.4 sobre OTP 28.5 y Debian trixie, con Node, `postgresql-client` y `tini`. Corre como usuario `dev`, con UID y GID configurables para hosts Linux.
- **Montajes:** el código se monta desde el host; `deps`, `_build`, `assets/node_modules` y las cachés de Mix, Hex y herramientas viven en volúmenes nombrados.
- **Recarga en vivo por sondeo:** `phoenix_live_reload` usa el backend `:fs_poll` (cada 500 ms) y Tailwind corre con `--poll`. El modo de vigilancia de esbuild ya sondea.
- **Garage sin CLI:** la imagen de Garage no tiene shell, así que `storage-init` es una imagen Alpine con `curl` y `jq` que usa la API de administración v2. Importa una clave de acceso fija, de modo que la configuración de la app no cambia entre reinicios, y aplica las reglas CORS con `UpdateBucket`. Es idempotente.
- **Correo:** en desarrollo, Swoosh usa el adaptador SMTP hacia Mailpit (`gen_smtp`). Ningún email sale del entorno.
- **Consola:** Phoenix corre como el nodo con nombre `amauta@app`, y `bin/dev iex` se conecta con `--remsh`.
- **Comandos:** `bin/dev` (bash) y `bin/dev.ps1` (PowerShell) exponen los mismos comandos.

## Consecuencias

- Un solo `bin/dev up` levanta todo. La primera vez tarda un par de minutos, por las dependencias y los binarios de Tailwind y esbuild.
- El sondeo consume algo de CPU en reposo. Si la E/S en Windows resulta lenta, la alternativa documentada es mover el repositorio a WSL2.
- La vista previa de correos de Swoosh (`/dev/mailbox`) queda vacía en desarrollo: los correos se ven en Mailpit (`http://localhost:8025`).
- Todas las credenciales de `compose.yaml` y `docker/garage/garage.toml` son solo de desarrollo.
