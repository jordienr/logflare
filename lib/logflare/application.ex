defmodule Logflare.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Logflare.Repo, []),
      supervisor(Logflare.AccountCache, []),
      supervisor(LogflareWeb.Endpoint, []),
      # init TableCounter before TableManager as TableManager calls TableCounter through table create
      supervisor(Logflare.TableCounter, []),
      supervisor(Logflare.SystemCounter, []),
      supervisor(Logflare.TableManager, []),
      {Task.Supervisor, name: Logflare.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Logflare.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    LogflareWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
