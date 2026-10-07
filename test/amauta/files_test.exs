defmodule Amauta.FilesTest do
  @moduledoc "Archivos con subida directa (RF-ARC-001 a 004 y 007) y foto de perfil."
  use Amauta.DataCase, async: true

  import Amauta.AccountsFixtures
  import Amauta.AuthorizationFixtures

  alias Amauta.{Accounts, Actions, Audit, Files, Scope, Storage}
  alias Amauta.Files.Actions.{CompleteUpload, RemoveAvatar, StartUpload}
  alias Amauta.Files.Detect
  alias Amauta.Storage.Local

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> :binary.copy(<<0>>, 100)

  defp scope_of(user), do: Scope.for_user(institution(), user)

  defp start(scope, filename, size, extra \\ %{}) do
    Actions.run(
      StartUpload,
      scope,
      Map.merge(%{"purpose" => "avatar", "filename" => filename, "size" => size}, extra)
    )
  end

  describe "tipo real" do
    test "reconoce por el contenido y exige que coincida con la extensión" do
      assert {:ok, "image/png"} = Detect.detect(@png, "foto.PNG")
      assert {:ok, "application/pdf"} = Detect.detect("%PDF-1.7 ...", "apunte.pdf")
      assert {:ok, "image/jpeg"} = Detect.detect(<<0xFF, 0xD8, 0xFF, 0xE0>>, "foto.jpg")
      assert {:error, :mismatch} = Detect.detect("%PDF-1.7", "foto.png")
      assert {:error, :mismatch} = Detect.detect(@png, "apunte.pdf")
      assert {:error, :unknown} = Detect.detect("<html><script>", "pagina.html")
    end

    test "los formatos con firma compartida se distinguen por la extensión" do
      zip = <<"PK", 3, 4, 0, 0>>

      assert {:ok, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"} =
               Detect.detect(zip, "tp.docx")

      assert {:error, :mismatch} = Detect.detect(zip, "foto.png")
      assert {:ok, "text/csv"} = Detect.detect("email,rol\nana@x.test,docente\n", "lista.csv")
      assert {:error, :mismatch} = Detect.detect(<<0, 1, 2, 3>>, "notas.txt")
    end
  end

  describe "subida simple" do
    test "pide la subida, sube directo y queda lista como foto de perfil" do
      user = user_fixture()
      scope = scope_of(user)

      assert {:ok, %{file: file, plan: %{mode: "single", url: url, headers: headers}}} =
               start(scope, "Mi Foto.png", byte_size(@png), %{"declared_type" => "image/png"})

      assert url =~ "local://"
      assert headers == %{"content-type" => "image/png"}
      assert file.status == "pending"
      assert file.key =~ ~r"^inst/#{institution().id}/avatars/[0-9a-f-]{36}/Mi-Foto.png$"

      # El navegador sube directo al almacenamiento.
      :ok = Storage.put(file.key, @png, content_type: "image/png")

      assert {:ok, %{status: "ready", content_type: "image/png"}} =
               Actions.run(CompleteUpload, scope, %{"file_id" => file.id})

      assert Accounts.get_user!(institution(), user.id).avatar_file_id == file.id
      assert "files.upload.complete" in Enum.map(Audit.list_events(scope), & &1.action)
    end

    test "una foto nueva reemplaza a la anterior y la borra" do
      user = user_fixture()
      scope = scope_of(user)

      upload = fn ->
        {:ok, %{file: file}} = start(scope, "foto.png", byte_size(@png))
        :ok = Storage.put(file.key, @png)
        {:ok, file} = Actions.run(CompleteUpload, scope, %{"file_id" => file.id})
        file
      end

      first = upload.()
      second = upload.()

      assert Accounts.get_user!(institution(), user.id).avatar_file_id == second.id
      assert {:error, :not_found} = Storage.head(first.key)
      assert Files.get(scope, first.id).status == "rejected"

      {:ok, _} = Actions.run(RemoveAvatar, scope, %{"user_id" => user.id})
      assert is_nil(Accounts.get_user!(institution(), user.id).avatar_file_id)
      assert {:error, :not_found} = Storage.head(second.key)
    end

    test "rechaza y borra si el contenido no es lo que dice ser" do
      scope = scope_of(user_fixture())
      {:ok, %{file: file}} = start(scope, "foto.png", 8)
      :ok = Storage.put(file.key, "%PDF-1.7")

      assert {:ok, %{status: "rejected", rejection_reason: "mismatch"}} =
               Actions.run(CompleteUpload, scope, %{"file_id" => file.id})

      assert {:error, :not_found} = Storage.head(file.key)
      assert is_nil(Accounts.get_user!(institution(), scope.user.id).avatar_file_id)
    end

    test "rechaza si no se subió nada o falta una parte" do
      scope = scope_of(user_fixture())
      {:ok, %{file: file}} = start(scope, "foto.png", 1000)

      assert {:ok, %{status: "rejected", rejection_reason: "not_uploaded"}} =
               Actions.run(CompleteUpload, scope, %{"file_id" => file.id})

      {:ok, %{file: file}} = start(scope, "otra.png", 1000)
      :ok = Storage.put(file.key, @png)

      assert {:ok, %{status: "rejected", rejection_reason: "incomplete"}} =
               Actions.run(CompleteUpload, scope, %{"file_id" => file.id})
    end
  end

  describe "límites (RF-ARC-003)" do
    test "tamaño y tipos permitidos para el propósito" do
      scope = scope_of(user_fixture())

      assert {:error, :too_large} = start(scope, "foto.png", 6 * 1024 * 1024)
      assert {:error, :type_not_allowed} = start(scope, "apunte.pdf", 100)
      assert {:error, :empty} = start(scope, "foto.png", 0)

      assert {:error, changeset} =
               Actions.run(StartUpload, scope, %{
                 "purpose" => "cualquiera",
                 "filename" => "x.png",
                 "size" => 1
               })

      assert %{purpose: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "subida por partes" do
    # En los tests, más de 1 KB va por partes de 512 bytes (config/test.exs).
    test "sube por partes, se reanuda y se completa" do
      user = user_fixture()
      scope = scope_of(user)
      part = Files.part_size()
      size = 2 * part + 10
      content = @png <> :binary.copy(<<1>>, size - byte_size(@png))

      {:ok, %{file: file, plan: %{mode: "multipart", parts: parts, done: []}}} =
        start(scope, "grande.png", size)

      assert Enum.map(parts, & &1.number) == [1, 2, 3]
      assert hd(parts).url =~ "partNumber=1"

      # Se sube la primera parte y se corta.
      :ok = Local.put_part(file.key, file.upload_id, 1, binary_part(content, 0, part))

      # Al volver a elegir el mismo archivo, sigue desde la parte 2.
      {:ok, %{file: same, plan: %{parts: rest, done: [1]}}} = start(scope, "grande.png", size)
      assert same.id == file.id
      assert Enum.map(rest, & &1.number) == [2, 3]

      # Sin todas las partes, todavía no se puede completar.
      :ok = Local.put_part(file.key, file.upload_id, 2, binary_part(content, part, part))
      :ok = Local.put_part(file.key, file.upload_id, 3, binary_part(content, 2 * part, 10))

      assert {:ok, %{status: "ready", size: ^size}} =
               Actions.run(CompleteUpload, scope, %{"file_id" => file.id})

      assert {:ok, ^content} = Storage.get(file.key)
    end
  end

  describe "permisos y aislamiento" do
    test "solo quien empezó la subida la confirma; otra persona no sube la foto ajena" do
      owner = scope_of(user_fixture())
      other = scope_of(user_fixture())
      {:ok, %{file: file}} = start(owner, "foto.png", byte_size(@png))

      assert {:error, :forbidden} = Actions.run(CompleteUpload, other, %{"file_id" => file.id})

      assert {:error, :forbidden} =
               start(other, "foto.png", 10, %{"owner_id" => owner.user.id})

      admin = member_scope("institution_admin")
      assert {:ok, _} = start(admin, "foto.png", 10, %{"owner_id" => owner.user.id})
    end

    test "los archivos de una institución no se ven desde otra" do
      scope = scope_of(user_fixture())
      {:ok, %{file: file}} = start(scope, "foto.png", byte_size(@png))
      b = Amauta.Fixtures.institution_fixture("inst_test_b")

      assert Storage.owned_by?(file.key, institution())
      refute Storage.owned_by?(file.key, b)
      assert is_nil(Files.get(b, file.id))
    end
  end
end
