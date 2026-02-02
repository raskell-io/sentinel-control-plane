defmodule SentinelCpWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SentinelCpWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SentinelCpWeb.Endpoint

      use SentinelCpWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SentinelCpWeb.ConnCase
    end
  end

  setup tags do
    SentinelCp.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Logs in a user via session for browser tests.
  Returns the conn with the user session set.
  """
  def log_in_user(%Plug.Conn{} = conn, user) do
    token = SentinelCp.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Sets up an API key and adds the Authorization header.
  Returns {conn, api_key}.
  """
  def authenticate_api(%Plug.Conn{} = conn, opts \\ []) do
    user = opts[:user] || SentinelCp.AccountsFixtures.user_fixture()
    project = opts[:project] || SentinelCp.ProjectsFixtures.project_fixture()

    {:ok, api_key} =
      SentinelCp.Accounts.create_api_key(%{
        name: "test-api-key",
        user_id: user.id,
        project_id: project.id,
        scopes: opts[:scopes] || ["read", "write"]
      })

    conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{api_key.key}")
    {conn, api_key}
  end
end
