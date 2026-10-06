# ADR-0004 · Multi-institución por schemas: implementación

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RNF-SEG-002, RF-ADM-002, RF-ADM-006, ERS 4.11 y 8.3 |

## Contexto

El ERS fija un schema `global` y uno por institución, con el prefijo explícito de Ecto en cada consulta y migraciones paralelas por institución. Este ADR registra cómo se implementó.

## Decisión

- **Registro:** `global.institutions` guarda slug, nombre, estado (`active` o `suspended`), zona horaria, idioma y el `schema_name`. Este último se genera una sola vez (`inst_` + 10 caracteres aleatorios) y no depende del slug, que se puede editar.
- **Prefijo obligatorio:** `Amauta.Repo.prepare_query/3` rechaza cualquier consulta sin prefijo (en la opción, en la consulta, en el `from` o en cada `join`). Las escrituras no pasan por `prepare_query`; las protege que las tablas de institución no existen en `public`.
- **Tenant:** las funciones de dominio reciben la institución o un mapa que la contiene (el futuro `Scope`) y usan `Amauta.Tenancy.opts/1`.
- **Migraciones por institución** (`priv/repo/tenant_migrations`): `Amauta.Tenancy.Migrator` compila cada archivo una vez por VM (con un lock, porque varias tareas pueden pedirlo a la vez) y se lo pasa a `Ecto.Migrator` como lista. `migrate_all/1` corre en paralelo con concurrencia acotada; el resultado de cada institución (`schema_version`, `migration_error`, `migrated_at`) queda en el registro, y un fallo no detiene a las demás.
- **Comando único:** `mix amauta.migrate` migra el schema global y todas las instituciones, informa el estado y termina con error si alguna falló. Lo usan el contenedor de desarrollo y el alias `test`.
- **Auditoría inmutable en la base:** cada institución tiene `audit_events` con un trigger que rechaza `UPDATE` y `DELETE`. La función del trigger vive en el mismo schema, para que el respaldo de una institución sea autónomo.
- **Zonas horarias:** `tzdata` con la actualización automática desactivada, porque Amauta no depende de la red en tiempo de ejecución (P4).

## Consecuencias

- **Tests y migraciones:** `Ecto.Migrator` ejecuta las migraciones en otro proceso, y dentro del sandbox ese trabajo se revierte en silencio. Por eso los tests que migran usan una conexión real compartida (`Amauta.TenantMigrationsHelper`), con `migration_lock: false` en `config/test.exs`, y limpian lo que crean.
- Los schemas de prueba (`inst_test_a` e `inst_test_b`) se crean una vez en `test_helper.exs`, y los datos de cada test van dentro del sandbox.
- Queda pendiente un `search_path` vacío para el usuario de la base, como defensa adicional para las escrituras.
