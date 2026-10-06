defmodule AmautaWeb.LocaleTest do
  @moduledoc "La interfaz sale en el idioma que corresponde (RF-I18N-001 y 004)."
  use AmautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Amauta.AccountsFixtures

  alias Amauta.{Accounts, Platform, Repo, Tenancy}
  alias AmautaWeb.Paths

  defp set_institution_locale(locale) do
    {:ok, institution} = Platform.update_institution(institution(), %{locale: locale})
    Process.put(:test_institution, institution)
  end

  test "con la institución en español, la interfaz habla con voseo", %{conn: conn} do
    set_institution_locale("es")
    {:ok, _lv, html} = live(conn, Paths.log_in(institution()))

    assert html =~ "Entrá para continuar."
    assert html =~ "Contraseña"
  end

  test "con la institución en inglés, la interfaz sale en inglés", %{conn: conn} do
    set_institution_locale("en")
    {:ok, _lv, html} = live(conn, Paths.log_in(institution()))

    assert html =~ "Log in to continue."
  end

  test "la preferencia de la persona le gana a la institución", %{conn: conn} do
    set_institution_locale("en")
    user = user_fixture()
    Repo.update_all(Accounts.User, [set: [locale: "es"]], Tenancy.opts(institution()))

    {:ok, _lv, html} = conn |> log_in_user(user) |> live(Paths.home(institution()))
    assert html =~ "Hola, #{user.first_name}"
  end

  test "los emails salen en el idioma de quien los recibe" do
    set_institution_locale("es")
    user = unconfirmed_user_fixture()

    {:ok, email} = Accounts.deliver_login_instructions(institution(), user, &"[TOKEN]#{&1}")
    assert email.subject == "Confirmá tu cuenta"
    assert email.text_body =~ "Hola, #{user.first_name}"
  end
end
