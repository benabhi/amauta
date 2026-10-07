defmodule AmautaWeb.FilesWebTest do
  @moduledoc "Descarga con permisos (RF-ARC-002) y foto de perfil desde Ajustes (RF-USR-001)."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  alias Amauta.{Accounts, Actions, Files, Scope, Storage}
  alias Amauta.Files.Actions.{CompleteUpload, StartUpload}
  alias AmautaWeb.Paths

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> :binary.copy(<<0>>, 100)

  defp uploaded_avatar(user) do
    scope = Scope.for_user(institution(), user)

    {:ok, %{file: file}} =
      Actions.run(StartUpload, scope, %{
        "purpose" => "avatar",
        "filename" => "foto.png",
        "size" => byte_size(@png)
      })

    :ok = Storage.put(file.key, @png)
    {:ok, file} = Actions.run(CompleteUpload, scope, %{"file_id" => file.id})
    file
  end

  describe "descarga" do
    test "redirige a una URL prefirmada después de verificar el permiso", %{conn: conn} do
      file = uploaded_avatar(user_fixture())
      conn = conn |> log_in_user(user_fixture()) |> get(Paths.file(institution(), file.id))

      assert "local://" <> _ = redirected_to(conn, 302)
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "con ?download=1 lo guarda con su nombre", %{conn: conn} do
      file = uploaded_avatar(user_fixture())

      conn =
        conn
        |> log_in_user(user_fixture())
        |> get(Paths.file(institution(), file.id) <> "?download=1")

      assert redirected_to(conn, 302) =~ "local://"
    end

    test "sin sesión no se descarga", %{conn: conn} do
      file = uploaded_avatar(user_fixture())
      conn = get(conn, Paths.file(institution(), file.id))
      assert redirected_to(conn) == Paths.log_in(institution())
    end

    test "un archivo pendiente o inexistente es 404", %{conn: conn} do
      user = user_fixture()

      {:ok, %{file: pending}} =
        Actions.run(StartUpload, Scope.for_user(institution(), user), %{
          "purpose" => "avatar",
          "filename" => "foto.png",
          "size" => 10
        })

      conn = log_in_user(conn, user)

      assert_raise AmautaWeb.NotFoundError, fn ->
        get(conn, Paths.file(institution(), pending.id))
      end

      assert_raise AmautaWeb.NotFoundError, fn ->
        get(conn, Paths.file(institution(), Ecto.UUID.generate()))
      end
    end
  end

  describe "foto de perfil" do
    test "se sube desde Ajustes y se muestra", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(Paths.settings(institution()))

      upload = element(view, "#avatar-upload")

      # Lo que hace el navegador: pedir la subida, subir y confirmar.
      render_hook(upload, "start", %{
        "filename" => "foto.png",
        "size" => byte_size(@png),
        "declared_type" => "image/png"
      })

      [file] = Amauta.Repo.all(Amauta.Files.StoredFile, Amauta.Tenancy.opts(institution()))
      :ok = Storage.put(file.key, @png)
      render_hook(upload, "complete", %{"file_id" => file.id})

      assert %{avatar_file_id: id} = Accounts.get_user!(institution(), user.id)
      assert id == file.id

      assert has_element?(
               view,
               ~s(#current-avatar img[src="#{Paths.file(institution(), file.id)}"])
             )

      view |> element(~s(button[phx-click="remove_avatar"])) |> render_click()
      refute has_element?(view, "#current-avatar img")
      assert Files.get(institution(), file.id).status == "rejected"
    end

    test "un archivo que no es imagen muestra el error", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(Paths.settings(institution()))
      upload = element(view, "#avatar-upload")

      render_hook(upload, "start", %{"filename" => "foto.png", "size" => 8})
      [file] = Amauta.Repo.all(Amauta.Files.StoredFile, Amauta.Tenancy.opts(institution()))
      :ok = Storage.put(file.key, "%PDF-1.7")

      html = render_hook(upload, "complete", %{"file_id" => file.id})
      assert html =~ "doesn&#39;t match its extension"

      html = render_hook(upload, "start", %{"filename" => "apunte.pdf", "size" => 8})
      assert html =~ "not allowed here"
    end
  end
end
