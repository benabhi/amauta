defmodule Amauta.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AmautaWeb.Telemetry,
        Amauta.Repo,
        {DNSCluster, query: Application.get_env(:amauta, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Amauta.PubSub},
        Amauta.Authorization.Cache,
        Amauta.Accounts.LoginThrottle,
        Amauta.Mail.RateLimit,
        {Oban, Application.fetch_env!(:amauta, Oban)}
      ] ++
        dev_code_reloader() ++
        [
          # Start to serve requests, typically the last entry
          AmautaWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Amauta.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Con recarga de código (desarrollo): recompilar solo si algo cambió.
  defp dev_code_reloader do
    if Application.get_env(:amauta, AmautaWeb.Endpoint)[:code_reloader],
      do: [AmautaWeb.DevCodeReloader.Watcher],
      else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AmautaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
