import Config

config :repro, ash_domains: [Repro.Blog], ecto_repos: [Repro.Repo]

# Any PostgreSQL 18 server, for example:
#   docker run --rm -p 54321:5432 -e POSTGRES_PASSWORD=postgres postgres:18
config :repro, Repro.Repo,
  url:
    System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost:54321/ash_temporal_repro"),
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

# Required by Ash 3.36.
config :ash, default_string_length_count: :codepoints
