# Cambios

Todos los cambios relevantes de Amauta. El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones, [Versionado Semántico](https://semver.org/lang/es/). Mientras la versión sea 0.x, cada versión menor cierra un hito del MVP (`docs/MVP.md`).

## [0.2.0] · 2026-10-07

Cierra **H2 · El aula**. Criterio de cierre verificado en desarrollo: una docente arma una unidad con una página y publica un aviso para la Comisión A. Sus 5 estudiantes reciben las dos notificaciones y el estudiantado de las otras comisiones, solo la de la página; los emails salen por la cola, uno por persona, agrupados.

### Editor y tablón

- Editor de bloques con menú «/»: títulos, listas, cita, recuadro destacado, código con resaltado, fórmula LaTeX, video incrustado y separador. El contenido se depura en el servidor.
- Tablón del curso en tiempo real: publicaciones para todo el curso o para una comisión, borrador que se guarda solo y editor plegado en una línea.
- Respuestas en hilo, menciones con «@», moderación (ocultar respuestas, cerrar respuestas y silenciar personas) y adjuntos con vista previa integrada.
- Publicaciones fijadas con orden y vencimiento.
- «Novedades del curso» (lo fijado y el contenido nuevo) separadas de la conversación. Cada publicación es una tarjeta compacta y tiene su propia página con toda la conversación.

### Contenido

- Unidades plegables con descripción, fechas opcionales y visibilidad (visible, oculta o programada), ordenables arrastrando o con el teclado.
- Páginas armadas con el editor de bloques y materiales con archivos y un enlace.
- Vista de cada elemento con índice lateral, «anterior / siguiente», visor integrado de imágenes, PDF, video y audio, y «marcar como hecho» con el progreso de cada unidad.
- Publicación programada, y aviso en el tablón cuando el estudiantado empieza a ver un elemento.

### Notificaciones y correo

- Centro de notificaciones en tiempo real, con campana, agrupación, filtros, «marcar todo como leído» y el «por qué lo recibís» de cada aviso.
- Preferencias por evento y por canal (en Amauta y por email).
- Todos los emails salen por una cola persistente, con prioridades, límite de tasa de la instancia, reintentos y lista de supresión por rebotes.
- Las notificaciones por email llegan agrupadas, con una plantilla con la institución y baja con un clic (RFC 8058).
- SMTP por variables de entorno y pantalla «Correo» en la administración, con el estado de la cola y un envío de prueba.

### Mejorado

- En desarrollo, las páginas cargan en ~0,1 s (antes ~1,8 s): el código se recompila solo cuando cambia, y LiveView ya no cae a long-poll.
- La barra de subida de archivos muestra el avance real y las etapas.

### Corregido

- Un ajuste nuevo del curso ya no queda nulo con builds incrementales.
- Las iniciales del avatar aparecen cuando la foto no carga.
- El tablón escala con hilos y publicaciones largas.

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

[0.2.0]: https://github.com/benabhi/amauta/releases/tag/v0.2.0
[0.1.0]: https://github.com/benabhi/amauta/releases/tag/v0.1.0
