defmodule Coophub.Backends.Gitlab do
  alias Coophub.Repos
  alias Coophub.Backends
  alias Coophub.Schemas.{Organization, Repository}

  defmacro __using__(_opts) do
    quote do
      @type request_data :: Backends.request_data()
      @type org :: Backends.org()
      @type repo :: Backends.repo()
      @type langs :: Backends.langs()
      @type topics :: Backends.topics()

      @behaviour Backends.Behaviour

      @impl Backends.Behaviour
      @spec prepare_request_org(String.t()) :: request_data
      def prepare_request_org(login) do
        prepare_request(login, "groups/#{login}")
      end

      @impl Backends.Behaviour
      @spec parse_org(map) :: org
      def parse_org(data) do
        data =
          %{
            "login" => data["path"],
            "url" => data["yml_data"]["url"],
            "html_url" => data["web_url"],
            "public_repos" => length(data["projects"])
          }
          |> Enum.into(data)

        Repos.to_struct(Organization, data)
      end

      @impl Backends.Behaviour
      @spec prepare_request_repos(org, integer) :: request_data
      def prepare_request_repos(%Organization{login: login}, limit) do
        prepare_request(
          login,
          "groups/#{login}/projects?include_subgroups=true&per_page=#{limit}&type=public&order_by=last_activity_at&sort=desc"
        )
      end

      @impl Backends.Behaviour
      @spec prepare_request_repo(org, map) :: request_data
      def prepare_request_repo(_organization, %{"path_with_namespace" => path_with_namespace}) do
        prepare_request(
          "projects/#{path_with_namespace}",
          "projects/#{URI.encode_www_form(path_with_namespace)}"
        )
      end

      @impl Backends.Behaviour
      @spec parse_repo(map) :: repo
      def parse_repo(data) do
        data =
          %{
            "stargazers_count" => data["star_count"],
            "key" => data["name"],
            "html_url" => data["web_url"],
            "topics" => data["tag_list"],
            "pushed_at" => data["last_activity_at"],
            # TODO: to review, "forks_count" exist but not "fork"
            "fork" => data["mirror"] || false,
            "owner" => %{
              "login" => data["namespace"]["full_path"],
              "avatar_url" => get_avatar_url(data)
            }
          }
          |> Enum.into(data)

        # sometimes open_issues_count does not exist!
        data = Map.put_new(data, "open_issues_count", 0)
        repo = Repos.to_struct(Repository, data)

        case repo.parent do
          %{"full_name" => name, "html_url" => url} ->
            Map.put(repo, :parent, %{name: name, url: url})

          _ ->
            repo
        end
      end

      @impl Backends.Behaviour
      @spec prepare_request_topics(org, repo) :: request_data
      def prepare_request_topics(_, _) do
        # topics are tag_list already set
        dont_request()
      end

      @impl Backends.Behaviour
      @spec parse_topics(map) :: topics
      def parse_topics(data) do
        data
      end

      @impl Backends.Behaviour
      @spec prepare_request_languages(org, repo) :: request_data
      def prepare_request_languages(_organization, %Repository{
            path_with_namespace: path_with_namespace
          }) do
        prepare_request(
          "projects/#{path_with_namespace}",
          "projects/#{URI.encode_www_form(path_with_namespace)}/languages"
        )
      end

      @impl Backends.Behaviour
      @spec parse_languages(langs) :: langs
      def parse_languages(languages) do
        languages
        |> Enum.reduce(%{}, fn {lang, percentage}, acc ->
          Map.put(acc, lang, %{"percentage" => percentage})
        end)
      end

      defp get_avatar_url(data) do
        case Map.get(data, "avatar_url") do
          nil ->
            case Map.get(data["namespace"], "avatar_url") do
              nil -> ""
              avatar_url -> "https://gitlab.com" <> avatar_url
            end

          avatar_url ->
            avatar_url
        end
      end

      def headers() do
        []
      end

      def full_url(path), do: "https://gitlab.com/api/v4/#{path}"

      defp prepare_request(name, path) do
        {name, full_url(path), headers()}
      end

      defp dont_request(login \\ ""), do: {login, nil, []}

      defoverridable full_url: 1,
                     headers: 0
    end
  end
end
