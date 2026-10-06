defmodule Amauta.Accounts.IdentityProvider do
  @moduledoc """
  Interfaz común de los proveedores de identidad (RF-AUT-008). La
  contraseña y el enlace mágico son los dos primeros; LDAP, OIDC o SAML se
  agregan como proveedores nuevos sin tocar cuentas, sesiones ni permisos.

  Un proveedor recibe la institución y los datos del formulario, y devuelve
  la persona autenticada. `:disconnect` lista tokens de sesión que dejaron
  de valer (por ejemplo, al confirmar una cuenta), para cerrar sus
  conexiones en vivo.
  """
  alias Amauta.Accounts.{User, UserToken}
  alias Amauta.Platform.Institution

  @type result ::
          {:ok, User.t(), %{disconnect: [UserToken.t()]}}
          | {:error, :invalid_credentials}

  @callback id() :: atom()
  @callback authenticate(Institution.t(), map()) :: result()
end
