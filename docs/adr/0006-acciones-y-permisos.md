# ADR-0006 · Capa de acciones y permisos

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | ERS 8.2, RF-ROL-001 a 005, RF-ROL-011, RF-ROL-012, Anexos B y C |

## Contexto

El ERS pide que toda operación del dominio sea una acción con nombre estable, permiso, efectos y resultado tipado, y que la interfaz, la API y los trabajos usen las mismas. También define un catálogo de permisos atómicos, roles de sistema y asignaciones por ámbito con cascada.

## Decisión

### Acciones

- Cada acción es un módulo con `use Amauta.Action`, que declara un nombre estable (`<contexto>.<recurso>.<operación>`), una descripción y parámetros tipados con tipos de Ecto. Implementa `authorize/2` y `run/2`, y opcionalmente `validate/1`, `audit/3` y `after_commit/3`.
- `Amauta.Actions.run/3` siempre recorre los mismos pasos:
  1. valida los parámetros;
  2. autoriza;
  3. ejecuta en una transacción, junto con el evento de auditoría;
  4. emite los efectos solo si la transacción se confirmó.

  Todo dentro de un span de telemetría `[:amauta, :action]`.
- El catálogo (`Amauta.Actions.all/0`) se puede listar en tiempo de ejecución. Los parámetros tipados son la base para generar el OpenAPI y el test de paridad de la API.
- Errores: `{:error, changeset}`, `{:error, :forbidden}` o `{:error, :not_found}`.

### Permisos

- **Catálogo** (`Amauta.Authorization.Permissions`): el Anexo B completo en el código, con riesgo y descripción. Pedir un permiso que no existe es un error, no un `false`.
- **Roles de sistema** (`Amauta.Authorization.Roles`): los ocho del Anexo C, definidos en el código. El Anexo C habla de grupos y de permisos «parciales»; la traducción a permisos atómicos está documentada en el módulo y se puede revisar. Los roles personalizados (V1) necesitarán una tabla.
- **Asignaciones**: `role_assignments` (persona, rol, ámbito `institution`, `pathway`, `course` o `section`, y el ID del ámbito), sin clave foránea al ámbito.
- **Cascada**: el protocolo `Amauta.Authorization.Target` da la cadena de ámbitos que contienen a un objetivo. Los permisos efectivos son la unión de los roles de las asignaciones de la institución y de esa cadena. En H0, `ScopeRef` representa trayectos, cursos y comisiones sin entidad; en H1 cada entidad implementa el protocolo.
- **Caché**: ETS, versionada por institución. Cualquier cambio de asignaciones sube la versión y deja obsoletas todas las entradas de esa institución.
- **Anti-escalada** (RF-ROL-005): para asignar o quitar un rol hace falta el permiso de gestión del ámbito y tener ya los permisos del rol. **Interpretación:** solo se comparan los permisos de riesgo medio y alto. Los de riesgo bajo son de participación (ver, responder, entregar lo propio). Con la regla literal, ni la docencia ni la gestión académica podrían matricular estudiantes, y eso contradice el Anexo C.

## Consecuencias

- Las LiveViews y los controladores no tocan el Repo para modificar: invocan acciones.
- **Migraciones en paralelo:** cada migración de institución usa dos conexiones (lock y ejecución). `mix amauta.migrate` dimensiona el pool según la concurrencia; con la aplicación en marcha, la concurrencia no debe pasar de la mitad del pool.
- **Pendientes:** el explicador de permisos (RF-ROL-006, V1), los ajustes locales (RF-ROL-013, V1), la invalidación de la caché entre nodos del clúster (cuando haya clúster) y el rol de superadministración de la plataforma, que llega con el asistente de primera ejecución.
