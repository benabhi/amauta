# Spike DEC-007 · Ash Framework 3

Rama `spike/ash`. Protocolo y criterios en el [ADR-0003](../adr/0003-framework-de-dominio.md).

Versiones: Ash 3.34.4, AshPostgres 2.14.2, AshPhoenix 2.3.25, AshJsonApi 1.7.1. Instalado con `mix igniter.install`.

## Qué se construyó

| Punto del protocolo | Implementación |
|---|---|
| 1. Tenancy por schema | `multitenancy :context` en cada recurso de institución; `Institution` con `manage_tenant` crea el schema y lo migra al registrarla. `Institution` implementa `Ash.ToTenant`. Se mantuvo la guardia de prefijo del Repo para las consultas de Ecto escritas a mano. |
| 2. Modelo | Recursos `Institution` (schema `global`), `User`, `Course`, `RoleAssignment`, `Post`, `Audit.Event`. Migraciones y snapshots generados con `mix ash_postgres.generate_migrations`. |
| 3. Permisos | Mismo catálogo y roles que en Ecto. Políticas: `HasCoursePermission` (chequeo simple sobre el `course_id` de la acción) y `CoursePermissionFilter` (chequeo de filtro para la lectura primaria). |
| 4. Capa de acciones | Las acciones de Ash *son* la capa: `Post.list` y `Post.create`, con interfaz de código en el dominio (`Feed.list_posts/2`, `Feed.create_post/2`). Auditoría con un cambio reutilizable (`Audit.Record`) dentro de la transacción. |
| 5. Interfaz | `FeedLive` con `AshPhoenix.Form` y `Ash.Notifier.PubSub`. `Amauta.Scope` implementa `Ash.Scope.ToOpts`, así que se pasa `scope:` y Ash obtiene actor e institución. |
| 6. API | AshJsonApi en `/api/v1` (JSON:API), rutas declaradas en el dominio; OpenAPI generado en `/api/v1/open_api`. |
| 7. Tests | Los mismos 27 casos que en Ecto, adaptados a la API de Ash. |

Verificado a mano: lo publicado por la API aparece en vivo en el LiveView abierto.

## Mediciones

| Criterio | Resultado |
|---|---|
| Líneas (sin generados) | Dominio 821 · Web 243 · Tests 331 · Configuración 96. Además, 1.169 líneas generadas (migraciones y snapshots). |
| Tiempo | Más que con Ecto: 3 rondas de corrección hasta los 27 tests en verde (ver problemas abajo). |
| Paridad de la API | Casi automática: declarar la ruta en el dominio alcanza para tener endpoint, serialización y OpenAPI. No hay schemas OpenAPI escritos a mano. |
| Rendimiento | Ver la comparación en el ADR-0003. |
| Facilidad para testear | Media: `manage_tenant` no es idempotente y obliga a insertar las instituciones de prueba por fuera de Ash. |

## Problemas encontrados (en orden)

1. **`manage_tenant` no es idempotente:** al crear una institución, AshPostgres aplica *todas* las migraciones de institución sin consultar las ya aplicadas. Si el schema ya existe, falla. `Ash.Seed` dispara el mismo efecto.
2. **Nombres reservados en el dominio:** `use Ash.Domain` define `can?/3`, que chocó con una función propia.
3. **Actualizaciones atómicas por defecto:** una acción que solo guarda el hash del token falló porque la validación de formato del email no se puede traducir a SQL. Requiere `require_atomic? false`.
4. **`load` necesita una lectura primaria:** sin `read` primaria en `Post`, `change load(:author)` falla con un `BadMapError` poco claro. Agregarla obliga a definir su política (se resolvió con un chequeo de filtro).
5. **Lecturas prohibidas devuelven lista vacía:** con la configuración que instala Igniter, una lectura sin permiso filtra en lugar de fallar. Para responder 403 hay que declarar `access_type :strict`.
6. **Exposición de datos en la API:** todo atributo `public?` es accesible por JSON:API si el cliente lo pide con `fields[...]`, aunque no esté en `default_fields`. El email de las personas quedó expuesto hasta marcarlo como no público. Para datos sensibles hacen falta políticas de campo (RF-ROL-008).

## Observaciones

- **Lo bueno:** con muy poco código se obtienen políticas declarativas, PubSub, formularios, JSON:API con OpenAPI, paginación por keyset y migraciones generadas. Ash detectó PostgreSQL 18 y usa `uuidv7()` nativo.
- **Lo difícil:** cuando algo falla, los errores son genéricos (`Unknown Error`, `BadMapError` dentro de Ash) y hay que leer el código fuente de la biblioteca para entenderlos. Los comportamientos por defecto (atómicos, filtrado de lecturas) son razonables, pero sorprenden.
- **Igniter** modificó el endpoint, el router, la configuración y `AGENTS.md` (quitó las guías de Ecto e instaló funciones PL/pgSQL en la base).
- **Elixir 1.20:** AshPhoenix y Spark compilan con advertencias del inferidor de tipos, igual que `open_api_spex` en la rama de Ecto.
