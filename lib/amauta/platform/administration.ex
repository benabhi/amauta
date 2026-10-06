defmodule Amauta.Platform.Administration do
  @moduledoc """
  Lo que hace la superadministración con las instituciones (RF-ADM-002 y
  RF-ADM-003). Cada operación queda en la auditoría de plataforma, y lo que
  cambia dentro de una institución, también en la suya.

  Estas operaciones no pasan por `Amauta.Actions`: las acciones operan
  dentro de una institución con el `Scope` de una de sus personas, y el
  personal de plataforma no es persona de ninguna.
  """
  import Ecto.Query

  alias Amauta.{Accounts, Audit, Authorization, Repo, Tenancy}
  alias Amauta.Platform.{AuditEvent, Institution, Staff}

  ## Instituciones

  @doc "Alta de una institución: registro, schema y migraciones."
  def create_institution(%Staff{} = staff, attrs) do
    case Tenancy.create_institution(attrs) do
      {:ok, institution} ->
        record!(staff, "platform.institution.create", institution, %{"slug" => institution.slug})
        {:ok, institution}

      error ->
        error
    end
  end

  def change_institution(institution \\ %Institution{}, attrs \\ %{}),
    do: Institution.changeset(institution, attrs)

  def update_institution(%Staff{} = staff, %Institution{} = institution, attrs) do
    with {:ok, updated} <- institution |> Institution.changeset(attrs) |> Repo.update() do
      record!(staff, "platform.institution.update", updated, changed(institution, updated))
      {:ok, updated}
    end
  end

  def suspend_institution(%Staff{} = staff, %Institution{} = institution),
    do: set_status(staff, institution, "suspended")

  def activate_institution(%Staff{} = staff, %Institution{} = institution),
    do: set_status(staff, institution, "active")

  defp set_status(staff, institution, status) do
    with {:ok, updated} <- institution |> Institution.status_changeset(status) |> Repo.update() do
      record!(staff, "platform.institution.#{status_action(status)}", updated, %{})
      {:ok, updated}
    end
  end

  defp status_action("suspended"), do: "suspend"
  defp status_action("active"), do: "activate"

  ## Administración de cada institución (RF-ADM-003)

  @doc "Personas con el rol de administración en toda la institución."
  def list_admins(%Institution{} = institution) do
    from(u in Accounts.User,
      join: a in Authorization.RoleAssignment,
      on: a.user_id == u.id,
      where: a.role == "institution_admin" and a.scope_type == "institution",
      order_by: [u.first_name, u.last_name],
      select: {u, a}
    )
    |> Repo.all(Tenancy.opts(institution))
  end

  @doc """
  Asigna la administración de una institución. Si la persona no existe, la
  da de alta. Le envía un enlace para entrar (`url_fun` arma la URL con el
  token).
  """
  def assign_admin(%Staff{} = staff, %Institution{} = institution, attrs, url_fun)
      when is_function(url_fun, 1) do
    email = attrs |> Map.get("email", Map.get(attrs, :email, "")) |> to_string() |> String.trim()

    result =
      Repo.transact(fn ->
        with {:ok, user} <- find_or_register(institution, email, attrs),
             {:ok, assignment} <- ensure_admin_role(staff, institution, user) do
          {:ok, {user, assignment}}
        end
      end)

    case result do
      {:ok, {user, assignment}} ->
        Authorization.invalidate(institution)
        Accounts.deliver_login_instructions(institution, user, url_fun)

        record!(staff, "platform.institution_admin.assign", institution, %{
          "user_id" => user.id,
          "assignment_id" => assignment.id
        })

        {:ok, user}

      error ->
        error
    end
  end

  @doc "Quita la administración de una persona."
  def revoke_admin(%Staff{} = staff, %Institution{} = institution, assignment_id) do
    case Authorization.get_assignment(institution, assignment_id) do
      %{role: "institution_admin"} = assignment ->
        {:ok, _} = Authorization.delete_assignment(institution, assignment)

        Audit.record!(institution, "authorization.role_assignment.delete",
          subject: assignment,
          metadata: %{"platform_staff_id" => staff.id, "role" => assignment.role}
        )

        record!(staff, "platform.institution_admin.revoke", institution, %{
          "user_id" => assignment.user_id
        })

        :ok

      _ ->
        {:error, :not_found}
    end
  end

  defp find_or_register(institution, email, attrs) do
    case email != "" && Accounts.get_user_by_email(institution, email) do
      %Accounts.User{} = user -> {:ok, user}
      _ -> Accounts.register_user(institution, attrs)
    end
  end

  defp ensure_admin_role(staff, institution, user) do
    existing =
      institution
      |> Authorization.list_assignments(user.id)
      |> Enum.find(&(&1.role == "institution_admin" and &1.scope_type == "institution"))

    if existing do
      {:ok, existing}
    else
      with {:ok, assignment} <-
             Authorization.create_assignment(institution, %{
               user_id: user.id,
               role: "institution_admin",
               scope_type: "institution"
             }) do
        Audit.record!(institution, "authorization.role_assignment.create",
          subject: assignment,
          metadata: %{"platform_staff_id" => staff.id, "role" => "institution_admin"}
        )

        {:ok, assignment}
      end
    end
  end

  ## Auditoría de plataforma

  @doc "Eventos de la auditoría de plataforma, del más reciente al más antiguo."
  def list_events(opts \\ []) do
    from(e in AuditEvent, order_by: [desc: e.inserted_at], limit: ^Keyword.get(opts, :limit, 50))
    |> Repo.all()
  end

  defp record!(staff, action, subject, metadata) do
    Repo.insert!(%AuditEvent{
      staff_id: staff.id,
      action: action,
      subject_type: "Institution",
      subject_id: subject.id,
      metadata: metadata
    })
  end

  defp changed(before, after_) do
    for field <- [:name, :short_name, :slug, :timezone, :locale],
        Map.get(before, field) != Map.get(after_, field),
        into: %{},
        do: {Atom.to_string(field), Map.get(after_, field)}
  end
end
