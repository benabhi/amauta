# ADR-0010 · Seguridad del acceso

| Campo | Valor |
|---|---|
| Estado | Aceptado |
| Fecha | 2026-10-06 |
| Requisitos y decisiones | RF-AUT-006, RF-AUT-008, RNF-SEG-012, RNF-SEG-018, RNF-SEG-019, RNF-DEV-009; completa los pendientes del ADR-0005 |

## Decisión

- **Límite de intentos** (`Amauta.Accounts.LoginThrottle`), en ETS:
  - **Por cuenta** (institución y email): 5 fallos en 15 minutos bloquean 1 minuto. Cada bloqueo nuevo duplica la duración, hasta 30 minutos.
  - **Por IP:** 20 fallos bloquean 5 minutos, con la misma progresión.
  - **Enlaces mágicos:** como máximo 3 seguidos por cuenta, para que nadie use la plataforma para inundar un buzón.
  - Un inicio de sesión correcto limpia el contador de la cuenta.
- **Respuestas uniformes:** un email inexistente y una contraseña incorrecta reciben el mismo mensaje. El aviso de bloqueo solo se envía si la cuenta existe, y no cambia la respuesta.
- **Avisos por email** (cola `mailers`, `SecurityEmailWorker`): cuenta bloqueada por intentos fallidos, e inicio de sesión desde un dispositivo nuevo. Los dispositivos se reconocen por el hash del agente de usuario (`user_devices`). El primer dispositivo de una persona no genera aviso.
- **Proveedores de identidad** (`Amauta.Accounts.IdentityProvider`): contraseña y enlace mágico implementan la misma interfaz, y el controlador autentica con `Accounts.authenticate/3`. LDAP, OIDC y SAML se suman como proveedores nuevos.
- **Inicio de sesión rápido de desarrollo:** `/:institution/dev/login` lista a las personas con sus roles y entra con un clic. Las rutas solo existen con `config :amauta, dev_login: true` (desarrollo y test).
- **Nombres de los roles** con Gettext (dominio `roles`), como el resto de la interfaz.

## Consecuencias

- **En los tests el limitador está apagado:** todos los tests salen de la misma IP y se bloquearían entre sí. Sus tests lo encienden y son sincrónicos.
- **Un nodo por vez:** el limitador vive en la memoria de cada nodo. Con un clúster, se reparte o se sincroniza (ERS 8.11).
- **IP del cliente:** detrás de un proxy, la IP real exige configurar los proxies de confianza (ERS 8.4). Queda para la imagen de producción (H4).
- **Pendiente para V1:** el captcha de prueba de trabajo tras varios fallos (RNF-SEG-016).
