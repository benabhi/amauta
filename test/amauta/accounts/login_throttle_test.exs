defmodule Amauta.Accounts.LoginThrottleTest do
  @moduledoc "Límite de intentos de inicio de sesión (RF-AUT-006, RNF-SEG-018)."
  # Sincrónico: enciende el limitador, que en los tests está apagado.
  use ExUnit.Case, async: false

  alias Amauta.Accounts.LoginThrottle

  @institution Ecto.UUID.generate()
  @ip {10, 0, 0, 1}

  setup do
    Application.put_env(:amauta, LoginThrottle, enabled: true)
    LoginThrottle.reset()

    on_exit(fn ->
      LoginThrottle.reset()
      Application.put_env(:amauta, LoginThrottle, enabled: false)
    end)
  end

  test "bloquea la cuenta al quinto intento fallido" do
    for _ <- 1..4 do
      assert :ok = LoginThrottle.record_failure(@institution, @ip, "ada@example.test")
      assert :ok = LoginThrottle.check(@institution, @ip, "ada@example.test")
    end

    assert :locked = LoginThrottle.record_failure(@institution, @ip, "ada@example.test")

    assert {:error, {:locked, seconds}} =
             LoginThrottle.check(@institution, @ip, "ada@example.test")

    assert seconds in 1..60
  end

  test "el bloqueo es por cuenta: otra cuenta sigue entrando desde la misma IP" do
    for _ <- 1..5, do: LoginThrottle.record_failure(@institution, @ip, "ada@example.test")

    assert {:error, _} = LoginThrottle.check(@institution, @ip, "ada@example.test")
    assert :ok = LoginThrottle.check(@institution, @ip, "beto@example.test")
  end

  test "el email no distingue mayúsculas ni espacios" do
    for _ <- 1..5, do: LoginThrottle.record_failure(@institution, @ip, "Ada@Example.test ")
    assert {:error, _} = LoginThrottle.check(@institution, @ip, "ada@example.test")
  end

  test "la misma cuenta en otra institución no se ve afectada" do
    for _ <- 1..5, do: LoginThrottle.record_failure(@institution, @ip, "ada@example.test")
    assert :ok = LoginThrottle.check(Ecto.UUID.generate(), {10, 0, 0, 2}, "ada@example.test")
  end

  test "una IP que prueba muchas cuentas queda bloqueada" do
    for n <- 1..20,
        do: LoginThrottle.record_failure(@institution, @ip, "persona#{n}@example.test")

    assert {:error, {:locked, seconds}} =
             LoginThrottle.check(@institution, @ip, "nueva@example.test")

    assert seconds > 60
    assert :ok = LoginThrottle.check(@institution, {10, 0, 0, 9}, "nueva@example.test")
  end

  test "un inicio de sesión correcto limpia el contador de la cuenta" do
    for _ <- 1..4, do: LoginThrottle.record_failure(@institution, @ip, "ada@example.test")
    LoginThrottle.record_success(@institution, "ada@example.test")

    for _ <- 1..4, do: LoginThrottle.record_failure(@institution, @ip, "ada@example.test")
    assert :ok = LoginThrottle.check(@institution, @ip, "ada@example.test")
  end

  test "limita los enlaces mágicos a tres seguidos por cuenta" do
    assert LoginThrottle.allow_magic_link?(@institution, "ada@example.test")
    assert LoginThrottle.allow_magic_link?(@institution, "ada@example.test")
    assert LoginThrottle.allow_magic_link?(@institution, "ada@example.test")
    refute LoginThrottle.allow_magic_link?(@institution, "ada@example.test")
    assert LoginThrottle.allow_magic_link?(@institution, "beto@example.test")
  end

  test "apagado, no limita nada" do
    Application.put_env(:amauta, LoginThrottle, enabled: false)
    for _ <- 1..10, do: LoginThrottle.record_failure(@institution, @ip, "ada@example.test")
    assert :ok = LoginThrottle.check(@institution, @ip, "ada@example.test")
  end
end
