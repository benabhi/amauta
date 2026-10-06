# ADR-0011 · Administración de la instancia

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-07 |
| Requisitos y decisiones | RF-ADM-001, 002, 003 y 006, RF-ROL-009, RNF-OBS-004, ERS 4.6 y 4.11 |

## Decisión

- **Personal de plataforma en el schema global** (`global.platform_staff`), con sus propios tokens de sesión. No es persona de ninguna institución y su sesión (`/admin`) es independiente de las de las instituciones. Entra solo con contraseña, así no depende del SMTP, y pasa por el mismo límite de intentos.
- **Asistente de primera ejecución** (`/setup`): mientras no exista ninguna superadministración, la portada lleva al asistente, que crea esa cuenta. Un lock evita que dos personas lo completen a la vez. Después, `/setup` lleva a `/admin`, donde se crea la primera institución. El almacenamiento, el SMTP y la URL base se configuran por variables de entorno, como define el MVP.
- **Operaciones sobre instituciones** (`Amauta.Platform.Administration`): alta, edición, suspensión y reactivación; reintento de migraciones; y asignación y revocación de la administración. Asignar da de alta a la persona si no existe, le asigna el rol en toda la institución y le envía un enlace para entrar.
- **Doble auditoría:** todo queda en la auditoría de plataforma (`global.platform_audit_events`, inmutable). Lo que cambia dentro de una institución, además, en la suya, con el ID del personal en los metadatos.
- **Fuera de la capa de acciones:** estas operaciones no pasan por `Amauta.Actions`, que opera dentro de una institución con el `Scope` de una de sus personas.
- **LiveDashboard** se mueve a `/admin/dashboard`, en todos los entornos, solo para el personal de plataforma.

## Consecuencias

- **Pendientes:** el rol de operación (sin acceso a contenidos) y la suplantación auditada del soporte (RF-ROL-009, V1); la gestión del personal desde la interfaz; y el dashboard v0 de la instancia (H4).
