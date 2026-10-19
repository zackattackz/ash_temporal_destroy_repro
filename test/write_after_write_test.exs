defmodule Repro.WriteAfterWriteTest do
  @moduledoc """
  On a temporal resource, destroys and some updates without `as_of`, given a
  record that came from an earlier read or write, are applied at an earlier
  point in the record's history instead of now.

  No write in these tests passes `as_of`, so every write is meant to happen at
  the time of the call. Each test compares the post's whole history, its rows
  in `posts`, as `{title, from, to}`. Each bound is named after the moment it
  should be:

    * `:created`, `:read` and `:updated`: the instants of the setup's create,
      read and update
    * `:write`: the instant of the write under test (anything from the moment
      it was called)
    * `nil`: an open end

  The short sleeps keep the instants apart.
  """
  use ExUnit.Case, async: false

  alias Repro.Blog.Post

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repro.Repo)
  end

  defp pause, do: Process.sleep(5)

  defp rows(id) do
    Repro.Repo.query!(
      "SELECT title, lower(valid_at), upper(valid_at) FROM posts WHERE id = $1 ORDER BY 2",
      [Ecto.UUID.dump!(id)]
    ).rows
  end

  # The lower bound of the post's newest row: when the last write so far began.
  defp last_write(id), do: id |> rows() |> List.last() |> Enum.at(1)

  # Runs the write under test, then returns the post's history with each bound
  # named after the moment it should be.
  defp history_after(id, instants, write) do
    pause()
    write_at = DateTime.utc_now()
    write.()

    names = Map.new(instants, fn {name, at} -> {at, name} end)

    name = fn
      nil -> nil
      at -> Map.get(names, at) || if(DateTime.compare(at, write_at) != :lt, do: :write, else: at)
    end

    for [title, from, to] <- rows(id), do: {title, name.(from), name.(to)}
  end

  # Creates "A". Returns the record the create returned.
  defp create do
    post = Ash.create!(Post, %{title: "A"})
    {post, %{created: last_write(post.id)}}
  end

  # Creates "A" and updates it to "B" (the `for_update` form, which works).
  # Returns the record the update returned.
  defp create_then_update do
    post = Ash.create!(Post, %{title: "A"})
    created = last_write(post.id)
    pause()
    updated = post |> Ash.Changeset.for_update(:update, %{title: "B"}) |> Ash.update!()
    {updated, %{created: created, updated: last_write(post.id)}}
  end

  # Creates "A" and reads it. Someone else then updates it to "B" through their
  # own changeset. Returns the earlier read, as a form or LiveView holds it.
  defp read_then_someone_updates do
    post = Ash.create!(Post, %{title: "A"})
    created = last_write(post.id)
    pause()
    read = Ash.get!(Post, post.id)
    pause()
    post |> Ash.Changeset.for_update(:update, %{title: "B"}) |> Ash.update!()
    {read, %{created: created, read: read.__metadata__.as_of, updated: last_write(post.id)}}
  end

  describe "writes in the past, given the record a create returned" do
    test "Ash.destroy/2" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn -> Ash.destroy!(post) end) ==
               [{"A", :created, :write}]
    end

    test "for_destroy, then Ash.destroy/2" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn ->
               post |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy!()
             end) == [{"A", :created, :write}]
    end

    test "a destroy code interface" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn -> Repro.Blog.destroy_post!(post) end) ==
               [{"A", :created, :write}]
    end

    test "Ash.update/3" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn -> Ash.update!(post, %{title: "B"}) end) ==
               [{"A", :created, :write}, {"B", :write, nil}]
    end
  end

  describe "writes in the past, given the record an update returned" do
    test "Ash.destroy/2" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn -> Ash.destroy!(updated) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "for_destroy, then Ash.destroy/2" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn ->
               updated |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy!()
             end) == [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "a destroy code interface" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn -> Repro.Blog.destroy_post!(updated) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "Ash.update/3" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn -> Ash.update!(updated, %{title: "C"}) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end
  end

  describe "writes in the past, given a record read before someone else's update" do
    test "Ash.destroy/2" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn -> Ash.destroy!(read) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "for_destroy, then Ash.destroy/2" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn ->
               read |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy!()
             end) == [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "a destroy code interface" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn -> Repro.Blog.destroy_post!(read) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}]
    end

    test "Ash.update/3" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn -> Ash.update!(read, %{title: "C"}) end) ==
               [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end
  end

  describe "writes now, as expected" do
    test "for_update, then Ash.update/2, given the record a create returned" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn ->
               post |> Ash.Changeset.for_update(:update, %{title: "B"}) |> Ash.update!()
             end) == [{"A", :created, :write}, {"B", :write, nil}]
    end

    test "an update code interface, given the record a create returned" do
      {post, instants} = create()

      assert history_after(post.id, instants, fn ->
               Repro.Blog.update_post!(post, %{title: "B"})
             end) == [{"A", :created, :write}, {"B", :write, nil}]
    end

    test "for_update, then Ash.update/2, given the record an update returned" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn ->
               updated |> Ash.Changeset.for_update(:update, %{title: "C"}) |> Ash.update!()
             end) == [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end

    test "for_update, then Ash.update/2, given a record read before someone else's update" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn ->
               read |> Ash.Changeset.for_update(:update, %{title: "C"}) |> Ash.update!()
             end) == [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end

    test "an update code interface, given the record an update returned" do
      {updated, instants} = create_then_update()

      assert history_after(updated.id, instants, fn ->
               Repro.Blog.update_post!(updated, %{title: "C"})
             end) == [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end

    test "an update code interface, given a record read before someone else's update" do
      {read, instants} = read_then_someone_updates()

      assert history_after(read.id, instants, fn ->
               Repro.Blog.update_post!(read, %{title: "C"})
             end) == [{"A", :created, :updated}, {"B", :updated, :write}, {"C", :write, nil}]
    end
  end

  test "prints the instants the records carry" do
    post = Ash.create!(Post, %{title: "A"})
    pause()
    updated = post |> Ash.Changeset.for_update(:update, %{title: "B"}) |> Ash.update!()
    read = Ash.get!(Post, post.id)

    IO.puts("""

    posts rows (title, from, to):        #{inspect(rows(post.id))}
    created record's __metadata__.as_of: #{inspect(post.__metadata__[:as_of])}
    updated record's __metadata__.as_of: #{inspect(updated.__metadata__[:as_of])}
    read record's __metadata__.as_of:    #{inspect(read.__metadata__[:as_of])}
    """)
  end
end
