# ADR-0001 · Registrar las decisiones de arquitectura

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RNF-MAN-006 |

## Contexto

Amauta lo desarrolla una sola persona por ahora, y el riesgo de continuidad es alto (ERS, riesgos). Las decisiones técnicas tienen que quedar explicadas para quien llegue después, incluida la propia persona dentro de un año.

## Decisión

Las decisiones de arquitectura se registran como ADR en `docs/adr/`, en español, con la plantilla de este directorio. El ERS y el MVP fijan el *qué*; los ADR, el *cómo* y el *por qué*.

## Consecuencias

- Cada PR que tome una decisión estructural incluye su ADR.
- Los ADR aceptados no se reescriben: se reemplazan con uno nuevo.
