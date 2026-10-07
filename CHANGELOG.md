# Cambios

Todos los cambios relevantes de Amauta. El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones, [Versionado Semántico](https://semver.org/lang/es/). Mientras la versión sea 0.x, cada versión menor cierra un hito del MVP (`docs/MVP.md`).

## [0.1.0] · 2026-10-07

Cierra **H0 · Fundaciones** y **H1 · Estructura**. Criterio de cierre de H1 verificado: una institución con 300 personas importadas por CSV, un trayecto y un curso con dos comisiones y sus estudiantes repartidos.

### Fundaciones (H0)

- Entorno de desarrollo con Docker Compose (Phoenix, PostgreSQL, Garage y Mailpit) y comandos `bin/dev`.
- Integración continua con GitHub Actions.
- Multi-institución con un schema de PostgreSQL por institución y consultas rechazadas sin prefijo.
- Autenticación por institución con contraseña y enlace mágico, límite de intentos, avisos de seguridad y modo sudo.
- Capa de acciones del dominio con autorización, validación, auditoría y efectos transaccionales; catálogo de permisos y roles de sistema con cascada por ámbito.
- Español rioplatense por defecto, formatos CLDR y terminología configurable por institución, con género gramatical.
- Trabajos en segundo plano con Oban, almacenamiento compatible con S3 y auditoría encadenada con verificación diaria.
- Sistema de diseño (tokens, Atkinson Hyperlegible Next, íconos Phosphor, modo claro y oscuro) y catálogo vivo de componentes.

### Estructura (H1)

- Superadministración de la instancia, asistente de instalación y gestión de instituciones.
- Directorio de personas con búsqueda y filtros, invitaciones por email, importación CSV con simulación y exportación auditada.
- Períodos lectivos con período actual.
- Trayectos con etapas ordenadas, estados y responsables.
- Cursos con portada generativa, pestañas fijas (Tablón, Contenido, Personas, Calificaciones y Ajustes), estados y ajustes mínimos; dentro de un trayecto, en una etapa y como obligatorios u optativos.
- Comisiones con horario y aula; docentes de comisión limitados a la suya.
- Matrículas con rol, estado, comisión y origen: manual, por CSV, por trayecto y con el código del curso. Dar de baja conserva el historial.
- Subida directa de archivos al almacenamiento con URLs prefirmadas, por partes y reanudable, con verificación del tipo real y descarga con permisos; foto de perfil.
- Inicio adaptado al rol: cursos propios para docentes y estudiantes; indicadores y pendientes para la administración.
- Paleta de comandos (Ctrl+K) con búsqueda de cursos, trayectos y personas, y ayuda de atajos; barra superior con buscador y menú de la cuenta.

### Corregido

- El aviso de desconexión ya no parpadea al recargar la página.
- Después de volver a autenticarse para entrar a Ajustes, se vuelve a Ajustes y no al inicio.

[0.1.0]: https://github.com/benabhi/amauta/releases/tag/v0.1.0
