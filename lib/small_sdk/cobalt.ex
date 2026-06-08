defmodule SmallSdk.Cobalt do
  @moduledoc false

  require Logger

  import SaveIt.SmallHelper.UrlHelper, only: [validate_url!: 1]

  def get_download_url(text) do
    url = String.split(text, "?") |> hd()

    req = build_request("/")
    res = Req.post(req, json: %{url: url})

    case handle_response(res) do
      {:ok, %{"status" => "tunnel", "url" => download_url}} ->
        {:ok, normalize_tunnel_url(download_url)}

      {:ok, %{"url" => download_url}} ->
        {:ok, download_url}

      {:ok, %{"status" => "picker", "picker" => picker_items}} ->
        {:ok, url, Enum.map(picker_items, &Map.get(&1, "url"))}

      {:ok, _} ->
        Logger.warning("cobalt response: #{inspect(res)}")
        {:error, "Can't get download url using Cobalt API"}

      {:error, msg} ->
        Logger.error("cobalt error: #{msg}")
        {:error, "Can't get download url using Cobalt API"}
    end
  end

  defp get_env do
    api_url = Application.fetch_env!(:save_it, :cobalt_api_url) |> validate_url!()

    {api_url}
  end

  defp build_request(path) do
    {api_url} = get_env()

    Req.new(
      base_url: api_url,
      url: path,
      headers: [
        {"Accept", "application/json"},
        {"Content-Type", "application/json"}
      ]
    )
  end

  defp normalize_tunnel_url(download_url) do
    {api_url} = get_env()
    tunnel_uri = URI.parse(download_url)
    api_uri = URI.parse(api_url)

    case {tunnel_uri, api_uri} do
      {%URI{path: "/tunnel"} = tunnel_uri, %URI{scheme: scheme, host: host, port: port}}
      when is_binary(scheme) and is_binary(host) ->
        %URI{tunnel_uri | scheme: scheme, host: host, port: port}
        |> URI.to_string()

      _ ->
        download_url
    end
  end

  @doc """
  Handle response from Cobalt API return body if status is 200..209
  """
  def handle_response({:ok, %{status: status, body: body}}) do
    case status do
      status when status in 200..209 ->
        {:ok, body}

      _ ->
        {:error, "Request failed with status #{status}: #{inspect(body)}"}
    end
  end

  def handle_response({:error, reason}) do
    Logger.error("Request failed: #{inspect(reason)}")
    {:error, "Request failed: #{inspect(reason)}"}
  end

  def handle_response!(%{status: status, body: body}) do
    case status do
      status when status in 200..209 ->
        body

      status ->
        Logger.error("Request failed with status #{status}: #{inspect(body)}")
        raise "Request failed with status #{status}"
    end
  end
end
