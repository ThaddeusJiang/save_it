defmodule SmallSdk.Cobalt do
  require Logger

  import SaveIt.SmallHelper.UrlHelper, only: [validate_url!: 1]

  def get_download_url(text) do
    url = String.split(text, "?") |> hd()

    req = build_request("/")
    res = Req.post(req, json: %{url: url})

    body = handle_response(res)

    case body do
      %{"url" => download_url} ->
        {:ok, download_url}

      %{"status" => "picker", "picker" => picker_items} ->
        {:ok, url, Enum.map(picker_items, &Map.get(&1, "url"))}

      %{"status" => "error", "text" => msg} ->
        Logger.warning("response.body is status error, text: #{msg}")
        {:error, msg}

      _ ->
        Logger.warning("response.body: #{inspect(body)}")
        {:error, "inner service error"}
    end
  end

  defp get_env() do
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

  @doc """
  Handle response from Cobalt API return body if status is 200..209
  """
  def handle_response({:ok, %{status: status, body: body}}) do
    case status do
      status when status in 200..209 ->
        body

      400 ->
        Logger.warning("Bad Request: #{inspect(body)}")
        raise "Bad Request"

      401 ->
        raise "Unauthorized"

      404 ->
        nil

      409 ->
        raise "Conflict"

      422 ->
        raise "Unprocessable Entity"

      503 ->
        raise "Service Unavailable"

      _ ->
        Logger.error("Unhandled status code #{status}: #{inspect(body)}")
        raise "Unknown error: #{status}"
    end
  end

  def handle_response({:error, reason}) do
    Logger.error("Request failed: #{inspect(reason)}")
    raise "Request failed"
  end

  def handle_response!(%{status: status, body: body}) do
    case status do
      status when status in 200..209 ->
        body

      status ->
        Logger.warning("Request failed with status #{status}: #{inspect(body)}")
        raise "Request failed with status #{status}"
    end
  end
end
