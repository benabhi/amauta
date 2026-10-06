defmodule Amauta.LocaleAndTerminologyTest do
  @moduledoc "Idioma, formatos locales y terminología (sección 5.30 y ERS 4.9)."
  use ExUnit.Case, async: true

  alias Amauta.{Locale, Terminology}
  alias Amauta.Accounts.User
  alias Amauta.Platform.Institution
  alias AmautaWeb.{Format, TestTerminologyMessages}

  defp institution(attrs \\ []), do: struct(%Institution{}, attrs)

  describe "resolución del idioma" do
    test "persona, después institución, después instancia" do
      assert Locale.resolve(%User{locale: "en"}, institution(locale: "es")) == "en"
      assert Locale.resolve(%User{locale: nil}, institution(locale: "en")) == "en"
      assert Locale.resolve(nil, nil) == "es"
    end

    test "ignora idiomas no soportados" do
      assert Locale.resolve(%User{locale: "fr"}, institution(locale: "xx")) == "es"
    end

    test "put/1 fija Gettext y CLDR" do
      Locale.put("en")
      assert Gettext.get_locale(AmautaWeb.Gettext) == "en"
      assert Amauta.Cldr.get_locale().cldr_locale_name == :en

      Locale.put("es")
      assert Gettext.get_locale(AmautaWeb.Gettext) == "es"
      assert Amauta.Cldr.get_locale().cldr_locale_name == :"es-AR"
    end
  end

  describe "formatos" do
    test "fechas en la zona y el idioma pedidos" do
      Locale.put("es")
      # 15 de marzo a las 03:00 UTC son las 00:00 en Buenos Aires.
      datetime = ~U[2026-03-15 03:00:00Z]

      assert Format.date(datetime, "America/Argentina/Buenos_Aires", :long) ==
               "15 de marzo de 2026"

      assert Format.date(datetime, "Etc/UTC", :long) == "15 de marzo de 2026"

      assert Format.date(~U[2026-03-15 02:00:00Z], "America/Argentina/Buenos_Aires", :long) ==
               "14 de marzo de 2026"
    end

    test "números y listas con las reglas del idioma" do
      Locale.put("es")
      assert Format.number(1234.5) == "1.234,5"
      assert Format.list(["Ana", "Beto", "Carla"]) == "Ana, Beto y Carla"

      Locale.put("en")
      assert Format.number(1234.5) == "1,234.5"
      assert Format.list(["Ana", "Beto", "Carla"]) == "Ana, Beto, and Carla"
    end
  end

  describe "terminología" do
    test "el preset genérico es el de por defecto" do
      i = institution()
      assert Terminology.name(i, :course) == "curso"
      assert Terminology.name(i, :course, 2) == "cursos"
      assert Terminology.title(i, :section) == "Comisión"
      assert Terminology.gender(i, :section) == :feminine
    end

    test "cada preset del Anexo E define todos los términos" do
      for preset <- Terminology.presets(), key <- Terminology.keys() do
        assert %{singular: s, plural: p, gender: g} =
                 Terminology.term(institution(terminology_preset: preset), key)

        assert s != "" and p != "" and g in [:masculine, :feminine]
      end
    end

    test "los ajustes de la institución pisan el preset" do
      i =
        institution(
          terminology_preset: "university",
          terminology: %{
            "course" => %{
              "singular" => "asignatura",
              "plural" => "asignaturas",
              "gender" => "feminine"
            }
          }
        )

      assert Terminology.name(i, :course, 3) == "asignaturas"
      assert Terminology.name(i, :pathway) == "carrera"
    end

    test "acepta un Scope además de la institución" do
      scope = %Amauta.Scope{institution: institution(terminology_preset: "postgraduate")}
      assert Terminology.name(scope, :course) == "seminario"
    end

    test "valida los ajustes" do
      ok = %{"course" => %{"singular" => "a", "plural" => "b", "gender" => "feminine"}}
      assert :ok = Terminology.validate_overrides(ok)

      assert {:error, _} =
               Terminology.validate_overrides(%{"curso" => ok["course"]})

      assert {:error, _} =
               Terminology.validate_overrides(%{
                 "course" => %{"singular" => "a", "plural" => "b", "gender" => "neutro"}
               })

      assert {:error, _} =
               Terminology.validate_overrides(%{
                 "course" => %{"singular" => " ", "plural" => "b", "gender" => "feminine"}
               })
    end

    test "gettext_term concuerda en género y número con el término" do
      Gettext.put_locale(AmautaWeb.TestGettext, "es")
      generic = institution()
      university = institution(terminology_preset: "university")

      assert TestTerminologyMessages.new_item(generic, :course) == "Nuevo curso"
      assert TestTerminologyMessages.new_item(university, :course) == "Nueva materia"
      assert TestTerminologyMessages.all_items(generic, :course) == "Todos los cursos"
      assert TestTerminologyMessages.all_items(university, :course) == "Todas las materias"
    end
  end
end
