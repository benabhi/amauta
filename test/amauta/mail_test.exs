defmodule Amauta.MailTest do
  @moduledoc "Correo: cola, serialización, supresión y límite de tasa (RF-EML-001 a 003)."
  # Cambia la configuración del límite de tasa: no en paralelo.
  use Amauta.DataCase, async: false

  import Swoosh.Email, except: [from: 2]

  alias Amauta.Mail
  alias Amauta.Mail.{RateLimit, SendWorker}

  defp email(to \\ "ana@example.test") do
    new()
    |> to({"Ana", to})
    |> Swoosh.Email.from({"Amauta", "no-responder@amauta.test"})
    |> subject("Hola")
    |> text_body("Texto")
    |> html_body("<p>Texto</p>")
    |> header("List-Unsubscribe", "<https://x/unsubscribe/t>")
  end

  test "la serialización conserva el email" do
    args = Mail.serialize(email())
    assert ^args = args |> Jason.encode!() |> Jason.decode!()
    copy = Mail.deserialize(args)
    assert copy.to == [{"Ana", "ana@example.test"}]
    assert copy.headers["List-Unsubscribe"] == "<https://x/unsubscribe/t>"
    assert copy.html_body == "<p>Texto</p>"
  end

  test "después de varios rebotes la dirección queda suprimida" do
    for _ <- 1..(Mail.max_bounces() - 1), do: Mail.record_bounce("rebota@example.test", "550")
    refute Mail.suppressed?("rebota@example.test")

    Mail.record_bounce("rebota@example.test", "550")
    assert Mail.suppressed?("rebota@example.test")

    assert {:cancel, :suppressed} =
             SendWorker.send_now(Mail.serialize(email("rebota@example.test")))
  end

  test "el límite de tasa hace esperar hasta la ventana siguiente" do
    previous = Application.get_env(:amauta, Mail)
    on_exit(fn -> Application.put_env(:amauta, Mail, previous) end)
    Application.put_env(:amauta, Mail, Keyword.put(previous, :rate_limits, minute: 2))

    # Un minuto que nadie usó.
    now = 4_102_444_800 + :rand.uniform(1_000_000) * 60
    assert :ok = RateLimit.acquire(now)
    assert :ok = RateLimit.acquire(now + 1)
    assert {:wait, wait} = RateLimit.acquire(now + 2)
    assert wait == 58
    assert :ok = RateLimit.acquire(now + 60)

    assert RateLimit.estimate(10) == 5 * 60
  end
end
