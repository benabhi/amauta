defmodule Amauta.Authorization do
  @moduledoc "Roles y asignaciones. El cálculo de permisos está en `Amauta.Authorization.Effective`."
  use Ash.Domain, otp_app: :amauta

  resources do
    resource Amauta.Authorization.RoleAssignment do
      define :assign_role, action: :create
      define :list_assignments, action: :for_user, args: [:user_id]
    end
  end
end
