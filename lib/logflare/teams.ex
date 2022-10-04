defmodule Logflare.Teams do
  @moduledoc false
  import Ecto.Query, warn: false
  alias Logflare.{Repo, Teams.Team, TeamUsers.TeamUser, Users, User}

  @doc "Returns a list of teams. Unfiltered."
  @spec list_teams() :: [Team.t()]
  def list_teams do
    Repo.all(Team)
  end

  @doc "Gets a single team. Raises `Ecto.NoResultsError` if the Team does not exist."
  @spec get_team!(String.t() | number()) :: Team.t()
  def get_team!(id), do: Repo.get!(Team, id)

  @doc "Gets a single team by attribute. Returns nil if not found"
  @spec get_team_by(keyword()) :: Team.t() | nil
  def get_team_by(keyword), do: Repo.get_by(Team, keyword)

  @doc "Gets a user's home team. A home team is set on the `User`'s `:team` key. Uses email as an identifier."
  @spec get_home_team(TeamUser.t()) :: Team.t() | nil
  def get_home_team(%TeamUser{email: email}) do
    case Users.get_by(email: email) |> Users.preload_team() do
      nil ->
        nil

      user ->
        user.team
    end
  end

  @doc "Preloads the `:user` assoc"
  @spec preload_user(nil | Team.t()) :: Team.t()
  def preload_user(nil), do: nil
  def preload_user(team), do: Repo.preload(team, :user)

  @doc "preloads the `:team_users` assoc"
  @spec preload_team_users(nil | Team.t()) :: Team.t()
  def preload_team_users(nil), do: nil
  def preload_team_users(team), do: Repo.preload(team, :team_users)

  @doc "Creates a team from a user."
  @spec create_team(User.t(), %{name: String.t()}) ::
          {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def create_team(user, %{name: _name} = attrs) do
    user
    |> Ecto.build_assoc(:team)
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a team"
  @spec update_team(Team.t(), map()) :: {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a Team"
  @spec delete_team(Team.t()) :: {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def delete_team(%Team{} = team), do: Repo.delete(team)

  @doc "Returns an `%Ecto.Changeset{}` for tracking team changes"
  @spec change_team(Team.t()) :: Ecto.Changeset.t()
  def change_team(%Team{} = team), do: Team.changeset(team, %{})
end
