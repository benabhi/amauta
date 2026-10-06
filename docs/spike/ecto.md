# Spike DEC-007 · Contextos de Phoenix con Ecto

Rama `spike/ecto`. Protocolo y criterios en el [ADR-0003](../adr/0003-framework-de-dominio.md).

## Qué se construyó

| Punto del protocolo | Implementación |
|---|---|
| 1. Tenancy por schema | `Amauta.Tenancy`: crea el schema `inst_<aleatorio>` y le aplica `priv/repo/tenant_migrations` con `Ecto.Migrator` y `prefix:`. `Amauta.Repo.prepare_query/3` rechaza toda consulta sin prefijo. |
| 2. Modelo | `Institution` (schema `global`), `User`, `Course`, `RoleAssignment`, `Post`, `Audit.Event`. Claves UUIDv7 generadas por Ecto. |
| 3. Permisos | Catálogo en `Authorization.Permissions`, roles de sistema en `Authorization.Roles`, asignaciones con ámbito institución o curso y cascada. |
| 4. Capa de acciones | Comportamiento `Amauta.Action` y `Amauta.Actions.run/3`: carga dentro de la institución, autoriza, ejecuta en una transacción, audita y emite efectos después del commit. Catálogo listable con `Amauta.Actions.all/0`. |
| 5. Interfaz | `FeedLive` con stream y PubSub; la institución sale de la ruta (`/:institution/c/:course/feed`) y las URLs, de `AmautaWeb.Paths`. |
| 6. API | `/api/v1/courses/:course_id/posts` (GET y POST) con token `amt_<slug>_<secreto>`; OpenAPI con `open_api_spex`, con el nombre de la acción como `operationId`. |
| 7. Tests | 27 tests: fuga entre instituciones, matriz de autorización (7 combinaciones de rol y ámbito), auditoría, LiveView en tiempo real, API y paridad acción↔API. |

Verificado a mano: lo publicado por la API aparece en vivo en el LiveView abierto.

## Mediciones

| Criterio | Resultado |
|---|---|
| Líneas (sin generados) | Dominio 543 · Web 389 (de las cuales 62 son schemas OpenAPI escritos a mano) · Tests 288 |
| Tiempo | La porción completa salió en una sesión, con los tests en verde a la primera ejecución. |
| Paridad de la API | Manual: cada operación se declara en el controlador y su schema OpenAPI se escribe aparte. La paridad se garantiza con un test que compara el catálogo de acciones con los `operationId`. |
| Rendimiento | Pendiente: se mide con el mismo script en las dos ramas. |
| Facilidad para testear | Alta: los tests de fuga y la matriz son ExUnit plano; el único cuidado es crear los schemas de institución fuera del sandbox (`test_helper.exs`). |

## Observaciones

- **Prefijo obligatorio:** la guardia de `prepare_query` cubre consultas, pero no `insert`/`update`/`delete`. Para esos, la red de seguridad es que las tablas de institución no existen en `public`, así que una escritura sin prefijo falla en la base. Conviene reforzarlo con un `search_path` vacío para el usuario de la app.
- **Todo es explícito:** cada función de contexto recibe la institución y pasa `Tenancy.opts/1`. Es repetitivo, pero se lee sin conocer nada fuera de Ecto.
- **OpenAPI a mano:** el schema de respuesta y la serialización (`post_json/1`) están duplicados. Con muchas acciones, esto es lo que más va a costar mantener.
- **`open_api_spex` y Elixir 1.20:** compila con advertencias del inferidor de tipos (cláusulas inalcanzables en `DeprecatedCast`). No afecta, pero es ruido en `--warnings-as-errors` si se aplicara a las dependencias.
- **Migraciones por institución:** `Ecto.Migrator` recarga el archivo para cada schema; se silencia la advertencia de módulo redefinido.
