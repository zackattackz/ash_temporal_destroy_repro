defmodule Repro.Repo do
  use AshPostgres.Repo, otp_app: :repro

  @impl true
  def installed_extensions, do: ["ash-functions", "btree_gist"]

  @impl true
  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}

  @impl true
  def prefer_transaction?, do: false
end
