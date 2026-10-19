# Temporal resources: destroys and `Ash.update/3` write as of the record's stamped instant

Minimal reproduction for an Ash bug. On a temporal resource, every record Ash
returns, from a write or a read, carries an instant in `__metadata__.as_of`.
Destroys in every form, and `Ash.update/3` given a record, write as of that
instant instead of now, although no `as_of` is passed. Every call returns
success. Records stay alive after a destroy, and updates land in the past and
never show up now.

- ash 3.36.1, ash_postgres 2.14.5, PostgreSQL 18
- Elixir 1.20.4, Erlang/OTP 29 (`.tool-versions`)
- One temporal resource, `Repro.Blog.Post`, with a `title`, and code interfaces
  `update_post` and `destroy_post`.

## Run

It needs PostgreSQL 18. The default `DATABASE_URL` points at port **54321**,
not 5432, so it doesn't use a Postgres you already run. A throwaway server:

```sh
docker run --rm -p 54321:5432 -e POSTGRES_PASSWORD=postgres postgres:18
```

Then:

```sh
mix deps.get
mix test
```

To use another server, set `DATABASE_URL`, for example
`postgres://user:pass@localhost:5432/ash_temporal_repro`.

### What it does to the database

`mix test` runs `mix ash.setup` first, which creates and migrates. It never
drops anything. On the server `DATABASE_URL` names, it:

- creates the database `ash_temporal_repro` if it doesn't exist;
- installs `btree_gist` and Ash's `ash_*` SQL functions in that database
  only;
- creates a `posts` table.

Each test runs in a transaction that is rolled back, so no rows are left. No
other database is read or changed. To remove what it created:

```sh
mix ecto.drop   # or stop the docker container above (--rm discards it)
```

## What the test does

`test/write_after_write_test.exs` sets up a post in one of three ways:

- **The record a create returned:** create "A", and keep the record the create
  returned.
- **The record an update returned:** create "A", update it to "B" with
  `for_update |> Ash.update!`, and keep the record that update returned.
- **A record read before someone else's update:** create "A" and read it.
  Someone else then updates it to "B" through their own changeset. Keep the
  earlier read, as a form or a LiveView holds it.

It then writes once more, without `as_of`, and compares the post's whole
history, its rows in `posts`, as `{title, from, to}`. Each bound is named after
the moment it should be: `:created`, `:read` and `:updated` for the setup's
steps, `:write` for the write under test, and `nil` for an open end. The short
sleeps between steps keep those instants apart.

Twelve of the nineteen tests fail:

| Write | Given | Expected history | Actual history |
|---|---|---|---|
| `Ash.destroy!(post)` | the record the create returned | `{"A", :created, :write}` | none: the record is gone, and so is its whole history |
| `for_destroy \|> Ash.destroy!` | the record the create returned | same | same as above |
| `destroy_post!(post)` | the record the create returned | same | same as above |
| `Ash.update!(post, %{title: "B"})` | the record the create returned | `{"A", :created, :write}, {"B", :write, nil}` | `{"B", :created, nil}`: right now, but "B" from its creation and "A" gone |
| `Ash.destroy!(updated)` | the record the update returned | `{"A", :created, :updated}, {"B", :updated, :write}` | `{"B", :updated, nil}`: still alive, and "A" gone |
| `for_destroy \|> Ash.destroy!` | the record the update returned | same | same as above |
| `destroy_post!(updated)` | the record the update returned | same | same as above |
| `Ash.update!(updated, %{title: "C"})` | the record the update returned | `{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}` | `{"C", :created, :updated}, {"B", :updated, nil}`: still "B", and "C" in place of "A" |
| `Ash.destroy!(read)` | a record read before someone else's update | `{"A", :created, :updated}, {"B", :updated, :write}` | `{"A", :created, :read}, {"B", :updated, nil}`: still alive, and "A" ends at the read |
| `for_destroy \|> Ash.destroy!` | a record read before someone else's update | same | same as above |
| `destroy_post!(read)` | a record read before someone else's update | same | same as above |
| `Ash.update!(read, %{title: "C"})` | a record read before someone else's update | `{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}` | `{"A", :created, :read}, {"C", :read, :updated}, {"B", :updated, nil}`: still "B", and "C" between the read and the other update |

The other six write tests pass, with the expected history: updates through
`for_update |> Ash.update!` and through the update code interface, given each of
the three records.

The last test prints the instants. The updated record carries the create's
instant, not the update's:

```
posts rows (title, from, to):        [["A", ~U[…48.674473Z], ~U[…48.682939Z]], ["B", ~U[…48.682939Z], nil]]
created record's __metadata__.as_of: ~U[…48.674473Z]
updated record's __metadata__.as_of: ~U[…48.674473Z]
read record's __metadata__.as_of:    ~U[…48.687854Z]
```

On `Ash.DataLayer.Ets`, the same calls fail with errors instead (a
`StaleRecord`, or a `KeyError` for `:__struct__`), so this reproduction uses
Postgres.
