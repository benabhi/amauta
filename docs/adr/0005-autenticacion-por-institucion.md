# ADR-0005 · Autenticación por institución

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RF-AUT-001 a RF-AUT-005, RF-AUT-007, RNF-SEG-002, ERS 4.6 y 8.4 |

## Contexto

Las personas y sus credenciales viven en el schema de cada institución (ERS 4.11). La base es `mix phx.gen.auth` (LiveView, Argon2id, enlace mágico y contraseña, modo sudo), que no contempla instituciones.

## Decisión

- **Datos:** `users` y `users_tokens` son tablas de institución. El email es único dentro de la institución, no en toda la instancia: la misma persona puede tener cuentas independientes en dos instituciones.
- **Contexto:** toda función de `Amauta.Accounts` recibe primero la institución o el `Amauta.Scope`.
- **Scope único:** `Amauta.Scope` lleva la institución y la persona (o `nil` para un visitante). Reemplaza al `Accounts.Scope` del generador.
- **Rutas:** en modo ruta, `/:institution/log-in`, `/:institution/settings`, etc. `AmautaWeb.Plugs.Tenant` resuelve la institución (404 si no existe, 403 si está suspendida) y todas las URLs salen de `AmautaWeb.Paths`.
- **Sesión:** la clave del token en la sesión y la cookie «recordarme» llevan el ID de la institución, así una sesión nunca vale en otra.
- **Sin autorregistro:** se quitó la pantalla de registro (RF-AUT-007 es V1). Las cuentas nacen sin contraseña al darlas de alta la institución, y la persona entra con un enlace mágico que confirma su email.
- **Personas suspendidas:** no inician sesión, y sus sesiones dejan de valer.
- **Textos:** todos pasan por `gettext`; la traducción al español llega con la pieza de idioma de H0.

## Consecuencias

- Iniciar sesión en una institución renueva la sesión del navegador y cierra la de otra institución abierta en el mismo navegador (protección contra la fijación de sesión). En modo subdominio o dominio propio, cada institución tiene su cookie y esto no ocurre.
- Pendiente en H0: protección contra fuerza bruta (RF-AUT-006), la interfaz de proveedores de identidad (RF-AUT-008), la lista de sesiones activas (RF-AUT-005) y el inicio de sesión rápido de desarrollo por rol (RNF-DEV-009).
