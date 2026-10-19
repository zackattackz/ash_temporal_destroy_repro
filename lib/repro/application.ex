defmodule Repro.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Repro.Repo], strategy: :one_for_one, name: Repro.Supervisor)
  end
end
