defmodule LogflareWeb.AuthController do
  use LogflareWeb, :controller
  use Phoenix.HTML

  plug Ueberauth

  alias Logflare.User
  alias Logflare.Repo

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
      api_key = :crypto.strong_rand_bytes(12) |> Base.url_encode64 |> binary_part(0, 12)
      user_params = %{token: auth.credentials.token, email: auth.info.email, provider: "github", api_key: api_key}
      changeset = User.changeset(%User{}, user_params)

      signin(conn, changeset)
  end

  def logout(conn, _params) do
      conn
      |> configure_session(drop: true)
      |> redirect(to: Routes.source_path(conn, :index))
  end

  def new_api_key(conn, _params) do
    case conn.params["undo"] do
      "true" ->
        %{assigns: %{user: user}} = conn
        new_api_key = user.old_api_key
        old_api_key = user.api_key
        user_params = %{api_key: new_api_key, old_api_key: old_api_key}

        changeset = User.changeset(user, user_params)
        Repo.update(changeset)

        conn
        |> put_flash(:info, "API key restored!")
        |> redirect(to: Routes.source_path(conn, :dashboard))
      nil ->
        %{assigns: %{user: user}} = conn
        new_api_key = :crypto.strong_rand_bytes(12) |> Base.url_encode64 |> binary_part(0, 12)
        old_api_key = user.api_key
        user_params = %{api_key: new_api_key, old_api_key: old_api_key}

        changeset = User.changeset(user, user_params)
        Repo.update(changeset)

        conn
        |> put_flash(:info, ["API key reset! ", link("Undo?", to: Routes.auth_path(conn, :new_api_key, undo: :true))])
        |> redirect(to: Routes.source_path(conn, :dashboard))
      end
  end

  defp signin(conn, changeset) do
    case insert_or_update_user(changeset) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Thanks for signing up!")
        |> put_session(:user_id, user.id)
        |> redirect(to: Routes.source_path(conn, :dashboard))
      {:ok_found_user, user} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> put_session(:user_id, user.id)
        |> redirect(to: Routes.source_path(conn, :dashboard))
      {:error, _reason} ->
        conn
        |> put_flash(:error, "Error signing in.")
        |> redirect(to: Routes.source_path(conn, :index))
    end
  end

  defp insert_or_update_user(changeset) do
    case Repo.get_by(User, email: changeset.changes.email) do
      nil ->
        Repo.insert(changeset)
      user ->
        {:ok_found_user, user}
    end
  end

end
