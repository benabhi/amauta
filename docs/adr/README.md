# Registros de decisiones de arquitectura (ADR)

Cada decisión de arquitectura relevante se registra acá (RNF-MAN-006). Un ADR no se edita una vez aceptado: si la decisión cambia, se escribe uno nuevo que lo reemplaza y se actualiza el estado del anterior.

## Cómo escribir uno

1. Copiar [`plantilla.md`](plantilla.md) como `NNNN-titulo-corto.md`, con el número siguiente.
2. Completarlo en estado **Propuesto** y abrir el PR junto con el código que lo implementa.
3. Al fusionarse, pasa a **Aceptado**.

Estados posibles: Propuesto, Aceptado, Rechazado, Reemplazado por ADR-NNNN.

## Índice

| ADR | Título | Estado |
|---|---|---|
| [0001](0001-registrar-decisiones.md) | Registrar las decisiones de arquitectura | Aceptado |
| [0002](0002-entorno-de-desarrollo.md) | Entorno de desarrollo con Docker Compose | Aceptado |
| [0003](0003-framework-de-dominio.md) | Framework de dominio: contextos con Ecto o Ash | Propuesto (recomienda Ecto) |
