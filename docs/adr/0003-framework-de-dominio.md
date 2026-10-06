# ADR-0003 · Framework de dominio: contextos con Ecto o Ash

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | DEC-007 (ERS, sección 8.14) |

## Contexto

El ERS deja abierta la elección entre los contextos de Phoenix con Ecto y Ash Framework 3, y pide decidir con evidencia mediante un spike acotado al comenzar el MVP. La comparación teórica está en la sección 8.14 del ERS.

## Protocolo del spike

Se construyó **la misma porción vertical** con cada enfoque, en ramas descartables:

- `spike/ecto`: contextos de Phoenix 1.8 con *scopes* y Ecto. Notas en `docs/spike/ecto.md` de esa rama.
- `spike/ash`: Ash 3 con AshPostgres, AshPhoenix y AshJsonApi. Notas en `docs/spike/ash.md` de esa rama.

La porción incluye:

1. **Tenancy por schema:** dos instituciones, cada una en su schema de PostgreSQL, resueltas por la URL.
2. **Modelo:** institución, curso y publicación del tablón.
3. **Permisos:** una docente publica en su curso; una estudiante solo lee; nadie ve datos de otra institución.
4. **Capa de acciones:** crear una publicación pasa por autorización, validación y un registro de auditoría.
5. **Interfaz:** un LiveView con la lista de publicaciones y un formulario, actualizado en tiempo real con PubSub.
6. **API:** las mismas operaciones expuestas por REST, con especificación OpenAPI.
7. **Tests:** fuga entre instituciones, matriz de autorización, LiveView y API.

Las dos ramas pasan los mismos 27 casos de prueba, y en las dos se verificó a mano que lo publicado por la API aparece en vivo en el LiveView.

## Resultados

| Criterio | Contextos con Ecto | Ash 3 |
|---|---|---|
| **Claridad del código** | Explícito: cada función recibe la institución y se lee sin conocer nada fuera de Ecto. Más repetitivo. | Declarativo y compacto en los recursos; la lógica de autorización y tenancy queda repartida entre DSL, cambios, preparaciones y chequeos. |
| **Líneas** (sin generados) | Dominio 543 · Web 389 · Tests 288 | Dominio 821 · Web 243 · Tests 331 · Config 96, más 1.169 líneas de migraciones y snapshots generados |
| **Tiempo de desarrollo** | Tests en verde a la primera ejecución. | 3 rondas de corrección, con 6 problemas (abajo) que exigieron leer el código fuente de Ash. |
| **Paridad de la API** | Manual: controlador y schemas OpenAPI a mano (62 líneas para 2 operaciones). Un test compara el catálogo de acciones con los `operationId`. | Casi automática: una ruta en el dominio da endpoint, serialización JSON:API, paginación y OpenAPI. |
| **Rendimiento** (dev, 2 corridas) | Listar 50: p50 0,77 ms · 7.800 op/s (20 procesos). Publicar: p50 2,0 ms · 1.600 op/s. | Listar 50: p50 2,0 ms · 3.300 op/s. Publicar: p50 4,2 ms · 280 op/s, con varianza alta. |
| **Facilidad para testear** | Alta: ExUnit plano. | Media: `manage_tenant` obliga a crear las instituciones de prueba por fuera de Ash. |
| **Seguridad por defecto** | Solo se expone lo que se serializa a mano. | Todo atributo público es accesible por la API con `fields[...]`: el email quedó expuesto hasta marcarlo como privado. |

### Problemas encontrados con Ash

1. `manage_tenant` aplica todas las migraciones sin consultar las ya aplicadas: no es idempotente.
2. `use Ash.Domain` define funciones (`can?/3`) que chocan con las propias.
3. Las actualizaciones son atómicas por defecto; una validación de formato obligó a desactivarlo.
4. `load` necesita una lectura primaria; sin ella falla con un `BadMapError` interno.
5. Una lectura sin permiso devuelve una lista vacía en vez de 403, salvo con `access_type :strict`.
6. Exposición de atributos públicos por la API, mencionada arriba.

Ninguno es grave por separado, y todos tienen solución documentada. Juntos muestran el costo principal de Ash para este proyecto: comportamientos implícitos que hay que conocer de antemano y errores que no explican la causa.

## Decisión

Se acepta la recomendación (2026-10-06): **contextos de Phoenix con Ecto**, con una capa de acciones propia (la del spike) como única puerta al dominio.

Motivos, en orden de peso:

1. **Una sola persona desarrolla y mantiene** (riesgo del ERS). El código explícito se depura y se explica sin depender del conocimiento profundo de un framework, y los errores apuntan a la causa.
2. **Seguridad multi-tenant y de datos personales:** en Ecto, nada se expone ni se filtra sin una línea de código que lo diga. En Ash, los valores por defecto (exposición de atributos, lecturas filtradas en silencio) exigen vigilancia constante.
3. **Rendimiento:** entre 2 y 5 veces más throughput en la misma porción. El día del parcial (RNF-REN-004) deja margen.
4. **Control de la tenancy:** las migraciones por institución, su estado y su paralelismo (RF-ADM-006) son propias y testeables, sin depender de `manage_tenant`.

**Lo que se resigna y cómo se compensa:** la paridad automática de la API, que es la mayor ventaja de Ash. Se compensa haciendo que cada acción declare su schema de entrada y salida, y generando desde el catálogo de acciones las operaciones OpenAPI y el test de paridad (RF-API-001). Es una inversión acotada dentro de H0, sobre la capa de acciones que ya existe.

## Consecuencias

- `spike/ecto` es la base de la capa de acciones, la tenancy, los permisos y el constructor de URLs de H0. Se rehace con calidad de producción (no se fusiona la rama tal cual).
- `spike/ash` queda archivada como referencia.
- Pendientes que el spike dejó a la vista: `search_path` vacío para el usuario de la base, generación de OpenAPI desde las acciones, y medir el rendimiento con un build de producción en la prueba de carga de H3.
