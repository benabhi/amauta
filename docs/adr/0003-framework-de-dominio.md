# ADR-0003 · Framework de dominio: contextos con Ecto o Ash

| Campo | Valor |
|---|---|
| Estado | Propuesto: la decisión se completa al cerrar el spike |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | DEC-007 (ERS, sección 8.14) |

## Contexto

El ERS deja abierta la elección entre los contextos de Phoenix con Ecto y Ash Framework 3, y pide decidir con evidencia mediante un spike acotado de 1 a 2 semanas al comenzar el MVP. La comparación está en la sección 8.14 del ERS.

## Protocolo del spike

Se construye **la misma porción vertical** con cada enfoque, en ramas descartables que salen de `develop`:

- `spike/ecto`: contextos de Phoenix 1.8 con *scopes* y Ecto.
- `spike/ash`: Ash 3 con AshPostgres, AshPhoenix y AshJsonApi.

La porción incluye:

1. **Tenancy por schema:** dos instituciones, cada una en su schema de PostgreSQL, resueltas por la URL.
2. **Modelo:** institución, curso y publicación del tablón.
3. **Permisos:** una docente publica en su curso; una estudiante solo lee; nadie ve datos de otra institución.
4. **Capa de acciones:** crear una publicación pasa por autorización, validación y un registro de auditoría.
5. **Interfaz:** un LiveView con la lista de publicaciones y un formulario, actualizado en tiempo real con PubSub.
6. **API:** las mismas operaciones expuestas por REST, con especificación OpenAPI.
7. **Tests:** fuga entre instituciones, matriz de autorización, LiveView y API.

## Criterios de comparación

| Criterio | Cómo se mide |
|---|---|
| Claridad del código | Líneas por funcionalidad y lectura cruzada: ¿se entiende sin conocer el framework? |
| Tiempo de desarrollo | Horas registradas por cada punto de la porción. |
| Paridad de la API | Esfuerzo para que la API cubra lo mismo que la interfaz, y calidad del OpenAPI. |
| Rendimiento | Latencia p95 de listar y crear publicaciones bajo carga, en el mismo hardware. |
| Facilidad para testear | Esfuerzo y claridad de los tests de fuga y de autorización. |
| Riesgos | Problemas encontrados, puntos donde hubo que salir del framework y madurez de la documentación. |

## Decisión

Pendiente: se completa con los resultados del spike.

## Consecuencias

Pendiente.
