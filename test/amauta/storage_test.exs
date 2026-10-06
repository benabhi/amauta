defmodule Amauta.StorageTest do
  @moduledoc "Almacenamiento: claves por institución y adaptador local (ERS 8.10)."
  use ExUnit.Case, async: true

  alias Amauta.Platform.Institution
  alias Amauta.Storage

  @institution %Institution{id: "01a11130-0000-7000-8000-000000000001"}

  describe "claves" do
    test "llevan la institución, la entidad, un UUIDv7 y el nombre saneado" do
      key = Storage.key(@institution, "submissions", "TP 1 - Álgebra (final).pdf")

      assert [
               "inst",
               "01a11130-0000-7000-8000-000000000001",
               "submissions",
               uuid,
               "TP-1-Algebra-final-.pdf"
             ] = String.split(key, "/")

      assert {:ok, _} = Ecto.UUID.cast(uuid)
      assert String.at(uuid, 14) == "7"
      assert Storage.owned_by?(key, @institution)
      refute Storage.owned_by?(key, %Institution{id: Ecto.UUID.generate()})
    end

    test "no son adivinables: dos archivos iguales tienen claves distintas" do
      refute Storage.key(@institution, "files", "a.txt") ==
               Storage.key(@institution, "files", "a.txt")
    end

    test "el nombre no puede escapar de su carpeta" do
      assert Storage.sanitize("../../etc/passwd") == "passwd"
      assert Storage.sanitize("..") == "file"
      assert Storage.sanitize("") == "file"
      assert String.length(Storage.sanitize(String.duplicate("a", 500))) == 120
    end

    test "la entidad tiene que ser un nombre simple" do
      assert_raise MatchError, fn -> Storage.key(@institution, "../x", "a.txt") end
    end
  end

  describe "adaptador local" do
    test "guarda, describe, lee y borra" do
      key = Storage.key(@institution, "files", "nota.txt")

      assert :ok = Storage.put(key, "hola", content_type: "text/plain")
      assert {:ok, %{size: 4, content_type: "text/plain"}} = Storage.head(key)
      assert {:ok, "hola"} = Storage.get(key)
      assert :ok = Storage.delete(key)
      assert {:error, :not_found} = Storage.head(key)
    end

    test "emite URLs de subida y descarga con vencimiento" do
      key = Storage.key(@institution, "files", "a.pdf")

      assert {:ok, %{url: "local://" <> _, headers: %{"content-type" => "application/pdf"}}} =
               Storage.presign_upload(key, content_type: "application/pdf")

      assert {:ok, url} = Storage.presign_download(key)
      assert url =~ "method=GET"
      assert url =~ "expires="
    end
  end
end
