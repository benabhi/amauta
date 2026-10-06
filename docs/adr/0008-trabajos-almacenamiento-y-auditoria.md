# ADR-0008 · Trabajos, almacenamiento y auditoría encadenada

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | ERS 8.2, 8.9 y 8.10, RF-ARC-001, 002 y 007, sección 5.25, DEC-006 |

## Decisión

### Trabajos en segundo plano

- **Oban** (edición open source) con su tabla en el schema `global` y las colas del ERS 8.9.
- Cada trabajo de una institución lleva `"institution_id"` en sus argumentos. `use Amauta.Worker` lo resuelve, cancela el trabajo si la institución ya no existe y llama a `perform_for/2`. `new_for/2` arma el trabajo a partir de una institución o un `Scope`.
- **Efectos transaccionales:** las acciones declaran sus efectos con `effects/3`, y `Amauta.Actions.run/3` los inserta en la misma transacción que el cambio. Si la acción falla, no se encola nada.
- En los tests, Oban corre en modo `:manual` y se verifica con `Oban.Testing`.

### Almacenamiento

- **`Amauta.Storage`** con dos adaptadores: S3 (ex_aws sobre Req; Garage en desarrollo) y disco local (tests).
- **Claves** `inst/{institución}/{entidad}/{uuidv7}/{nombre-saneado}`: aisladas por institución y no adivinables. El nombre se sanea (sin rutas, sin acentos ni símbolos, con un largo acotado).
- **URLs prefirmadas** de subida (`PUT`, 15 minutos, con el tipo de contenido fijado) y de descarga (5 minutos, con `Content-Disposition`). Se firman con el host público (`S3_PUBLIC_ENDPOINT`), que es el que usa el navegador; el resto de las operaciones van por el endpoint interno.
- **Pruebas contra Garage real:** `test/amauta/storage_s3_integration_test.exs`, marcadas como `:integration` y excluidas por defecto. Se corren con `bin/dev mix test --only integration`.

### Auditoría encadenada

- Cada evento guarda su número de secuencia, el hash del anterior y el suyo: SHA-256 de una serialización canónica, con los metadatos ordenados por clave. Un lock por institución dentro de la transacción (`pg_advisory_xact_lock`) evita que la cadena se bifurque con escrituras concurrentes.
- `Amauta.Audit.verify_chain/1` recalcula la cadena y devuelve la primera secuencia alterada, faltante o fuera de orden. `Amauta.Audit.VerifyAllWorker` corre todos los días a las 3:30 (Oban Cron) y encola una verificación por institución.
- La cadena complementa el trigger que rechaza `UPDATE` y `DELETE`: el trigger frena los cambios accidentales, y la cadena delata los que se hacen por fuera de la aplicación (por ejemplo, desactivando el trigger).

## Consecuencias

- **Validación del archivo subido:** confirmar la subida (verificar el objeto y su tipo real, RF-ARC-004) y registrar sus metadatos queda para la pieza de archivos de H1, que usa estas URLs.
- **Verificación rota:** por ahora se registra como error y el trabajo falla. Las alertas llegan con la consola de errores (H4).
- **Escrituras de auditoría:** se serializan por institución. Es lo esperado para un registro con cadena; si en algún momento pesa, se puede encadenar por lotes.
