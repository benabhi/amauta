defmodule Amauta.Authorization.Permissions do
  @moduledoc """
  Catálogo de permisos atómicos (RF-ROL-001, Anexo B del ERS).

  Convención `<ámbito>.<recurso>.<acción>`. El ámbito indica el nivel más
  alto en el que el permiso tiene sentido; una asignación en un nivel
  superior lo hereda en cascada. Los permisos `platform.*` son del personal
  de la instancia y no se asignan dentro de una institución.

  El catálogo vive en el código y se versiona con él: es la única fuente de
  verdad de los permisos que existen.
  """

  @type risk :: :low | :medium | :high
  @type t :: %{key: String.t(), risk: risk(), description: String.t()}

  @catalog [
    # Plataforma
    {"platform.institutions.manage", :high, "Crear, suspender y eliminar instituciones"},
    {"platform.settings.manage", :high, "Configurar la instancia"},
    {"platform.health.view", :low, "Ver salud, telemetría y colas"},
    {"platform.logs.view", :medium, "Ver logs y errores del servidor"},
    {"platform.impersonate", :high, "Suplantar a una persona (auditado)"},
    {"platform.backups.manage", :high, "Respaldar y restaurar"},
    {"platform.email.manage", :medium, "Configurar el SMTP global y los límites de tasa"},
    {"platform.federation.manage", :high, "Gestionar nodos y mover instituciones"},
    # Institución
    {"institution.settings.update", :medium, "Editar la configuración general"},
    {"institution.branding.update", :low, "Editar la identidad visual"},
    {"institution.terminology.update", :low, "Editar la terminología"},
    {"institution.auth.manage", :high, "Configurar la autenticación"},
    {"institution.domains.manage", :medium, "Gestionar dominios propios"},
    {"institution.roles.manage", :high, "Crear y editar roles y ajustes locales"},
    {"institution.users.view", :medium, "Ver el directorio de personas"},
    {"institution.users.manage", :high, "Crear, editar, suspender e importar personas"},
    {"institution.users.view_sensitive", :high,
     "Ver campos sensibles (DNI, salud, adaptaciones)"},
    {"institution.periods.manage", :medium, "Gestionar períodos lectivos"},
    {"institution.taxonomy.manage", :low,
     "Gestionar categorías, etiquetas y campos personalizados"},
    {"institution.pathways.create", :medium, "Crear trayectos"},
    {"institution.courses.create", :low, "Crear cursos"},
    {"institution.announcements.publish", :medium, "Publicar avisos institucionales"},
    {"institution.notifications.manage", :medium,
     "Configurar las notificaciones en cascada y los eventos obligatorios"},
    {"institution.email.manage", :medium,
     "Configurar el SMTP y las plantillas, y ver el registro de envíos"},
    {"institution.messages.review_reported", :high,
     "Revisar conversaciones denunciadas (auditado)"},
    {"institution.reports.view", :medium, "Ver reportes institucionales"},
    {"institution.data.export", :high, "Exportar datos de la institución"},
    {"institution.audit.view", :medium, "Ver la auditoría"},
    {"institution.integrations.manage", :high,
     "Gestionar cuentas de servicio, tokens y webhooks"},
    {"institution.library.manage", :low, "Gestionar la biblioteca institucional"},
    {"institution.imports.manage", :high, "Ejecutar y deshacer importaciones masivas"},
    {"institution.storage.manage", :medium,
     "Archivar en frío, restaurar y purgar según la retención"},
    {"institution.users.merge", :high, "Fusionar personas duplicadas"},
    {"institution.security.manage", :high,
     "Configurar la seguridad institucional (contraseñas, sesiones, IP permitidas)"},
    {"institution.activity.view", :high,
     "Ver la actividad detallada de cualquier persona (auditado)"},
    {"institution.backups.manage", :high, "Respaldar y restaurar la institución"},
    {"institution.certificates.manage_templates", :low, "Gestionar plantillas de certificados"},
    # Trayecto
    {"pathway.view", :low, "Ver el trayecto"},
    {"pathway.update", :medium, "Editar datos y ajustes"},
    {"pathway.structure.update", :medium, "Editar etapas y cursos del trayecto"},
    {"pathway.archive", :medium, "Archivar o enviar a la papelera"},
    {"pathway.enrollments.manage", :medium, "Matricular y gestionar cohortes"},
    {"pathway.feed.post", :low, "Publicar en el tablón del trayecto"},
    {"pathway.progress.view_all", :medium, "Ver el progreso de todas las personas"},
    {"pathway.cycle.clone", :medium, "Crear un nuevo ciclo"},
    {"pathway.reports.view", :medium, "Ver reportes del trayecto"},
    # Curso (asignado en una comisión, se limita a esa comisión)
    {"course.view", :low, "Ver el curso"},
    {"course.update", :medium, "Editar los ajustes"},
    {"course.archive", :medium, "Archivar, archivar en frío o enviar a la papelera"},
    {"course.duplicate", :medium,
     "Duplicar el curso, exportarlo como paquete o copiar su contenido a otro curso"},
    {"course.activity.view", :medium,
     "Ver la actividad de los estudiantes del curso (quién vio, descargó o entregó)"},
    {"course.content.view_hidden", :low, "Ver contenido oculto o programado"},
    {"course.content.manage", :medium, "Crear, editar, ordenar y eliminar unidades y elementos"},
    {"course.feed.post", :low, "Publicar en el tablón"},
    {"course.feed.reply", :low, "Responder en el tablón"},
    {"course.feed.pin", :low, "Fijar publicaciones"},
    {"course.feed.moderate", :medium, "Ocultar, eliminar y silenciar"},
    {"course.assignments.manage", :medium, "Crear y editar tareas"},
    {"course.submissions.create_own", :low, "Entregar tareas propias"},
    {"course.submissions.view_all", :medium, "Ver todas las entregas"},
    {"course.submissions.grade", :medium, "Calificar y devolver entregas"},
    {"course.submissions.extend", :medium, "Otorgar prórrogas y excepciones"},
    {"course.assessments.manage", :medium, "Crear y editar evaluaciones y el banco de preguntas"},
    {"course.assessments.monitor", :low, "Ver el monitor en vivo"},
    {"course.attempts.create_own", :low, "Rendir evaluaciones"},
    {"course.attempts.manage", :medium, "Reabrir intentos y otorgar adaptaciones"},
    {"course.grades.view_own", :low, "Ver las notas propias"},
    {"course.gradebook.view_all", :medium, "Ver el libro de calificaciones"},
    {"course.gradebook.edit", :high, "Editar notas"},
    {"course.gradebook.override_final", :high, "Reemplazar la nota final"},
    {"course.gradebook.publish", :medium, "Publicar notas"},
    {"course.gradebook.lock", :high, "Cerrar y reabrir las calificaciones"},
    {"course.attendance.take", :low, "Tomar asistencia"},
    {"course.attendance.manage", :medium, "Gestionar sesiones y justificaciones"},
    {"course.people.view", :low, "Ver participantes"},
    {"course.people.view_contact", :medium, "Ver datos de contacto"},
    {"course.people.enroll", :medium, "Matricular y dar de baja"},
    {"course.sections.manage", :medium, "Gestionar comisiones y grupos"},
    {"course.messages.send_teachers", :low, "Escribir al equipo docente"},
    {"course.messages.send_peers", :low, "Escribir a compañeros"},
    {"course.messages.send_selection", :low, "Escribir a una selección de personas"},
    {"course.notifications.manage", :low, "Configurar qué notifica el curso"},
    {"course.certificates.issue", :medium, "Emitir y revocar certificados"},
    {"course.analytics.view", :medium, "Ver la analítica del curso"},
    {"course.view_as", :high, "Ver el curso como otra persona (auditado)"},
    # Personales (siempre sobre lo propio)
    {"self.profile.update", :low, "Editar el perfil propio"},
    {"self.data.export", :low, "Descargar los datos propios"},
    {"self.tokens.manage", :medium, "Gestionar los tokens de API propios"},
    {"self.accounts.link", :low, "Vincular cuentas de otras instituciones"}
  ]

  @by_key Map.new(@catalog, fn {key, risk, description} ->
            {key, %{key: key, risk: risk, description: description}}
          end)

  @keys Enum.map(@catalog, &elem(&1, 0))

  @doc "Todas las claves del catálogo, en el orden del Anexo B."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Claves que empiezan con un prefijo, por ejemplo `\"course.\"`."
  @spec keys_with_prefix(String.t()) :: [String.t()]
  def keys_with_prefix(prefix), do: Enum.filter(@keys, &String.starts_with?(&1, prefix))

  @spec get(String.t()) :: t() | nil
  def get(key), do: Map.get(@by_key, key)

  @spec exists?(String.t()) :: boolean()
  def exists?(key), do: Map.has_key?(@by_key, key)

  @doc "Falla si la clave no está en el catálogo: evita errores de tipeo silenciosos."
  @spec fetch!(String.t()) :: t()
  def fetch!(key) do
    Map.get(@by_key, key) || raise ArgumentError, "unknown permission: #{inspect(key)}"
  end
end
