defmodule Repro.Blog.Post do
  use Ash.Resource,
    domain: Repro.Blog,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "posts"
    repo Repro.Repo
  end

  temporal do
    strategy :context
    attribute :valid_at
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:title], update: [:title]]
  end
end
