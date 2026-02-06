defmodule SentinelCpWeb.E2E.LoginFlowTest do
  @moduledoc """
  E2E tests for user login flows.

  Tests valid login, invalid credentials, and redirect to login.
  """
  use SentinelCpWeb.FeatureCase

  @moduletag :e2e

  import Wallaby.Query

  describe "login flow" do
    feature "valid login redirects to dashboard", %{session: session} do
      user = SentinelCp.AccountsFixtures.user_fixture(%{
        email: "test@example.com",
        password: "SecurePassword123!"
      })

      session
      |> visit("/login")
      |> assert_has(css("h1", text: "Log in"))
      |> fill_in(text_field("Email"), with: user.email)
      |> fill_in(css("input[type='password']"), with: "SecurePassword123!")
      |> click(button("Log in"))
      |> assert_has(css("nav", text: "Dashboard"))
    end

    feature "invalid email shows error", %{session: session} do
      session
      |> visit("/login")
      |> fill_in(text_field("Email"), with: "nonexistent@example.com")
      |> fill_in(css("input[type='password']"), with: "SomePassword123!")
      |> click(button("Log in"))
      |> assert_has(css(".alert", text: "Invalid"))
    end

    feature "invalid password shows error", %{session: session} do
      user = SentinelCp.AccountsFixtures.user_fixture()

      session
      |> visit("/login")
      |> fill_in(text_field("Email"), with: user.email)
      |> fill_in(css("input[type='password']"), with: "WrongPassword123!")
      |> click(button("Log in"))
      |> assert_has(css(".alert", text: "Invalid"))
    end

    feature "empty form shows validation", %{session: session} do
      session
      |> visit("/login")
      |> click(button("Log in"))
      |> assert_has(css(".alert"))
    end
  end

  describe "redirect to login" do
    feature "unauthenticated user redirected to login", %{session: session} do
      org = SentinelCp.OrgsFixtures.org_fixture()

      session
      |> visit("/orgs/#{org.slug}/dashboard")
      |> assert_has(css("h1", text: "Log in"))
    end

    feature "protected routes require authentication", %{session: session} do
      session
      |> visit("/audit")
      |> assert_has(css("h1", text: "Log in"))
    end
  end

  describe "authenticated navigation" do
    feature "logged in user can access protected pages", %{session: session} do
      {session, _user} = create_and_login_user(session)

      session
      |> assert_has(css("nav"))
      |> visit("/audit")
      |> assert_has(css("h1", text: "Audit"))
    end
  end
end
