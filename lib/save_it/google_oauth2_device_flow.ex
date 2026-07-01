defmodule SaveIt.GoogleOAuth2DeviceFlow do
  @moduledoc false

  require Logger
  @google_oauth_api_url "https://oauth2.googleapis.com"

  def get_device_code do
    with {:ok, {client_id, _client_secret}} <- get_env() do
      body = %{
        client_id: client_id,
        scope: "https://www.googleapis.com/auth/drive.file"
      }

      "/device/code"
      |> build_request()
      |> Req.post(form: body)
      |> handle_response()
    end
  end

  defp handle_response({:ok, %{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: %{"error" => error} = body}}) do
    Logger.warning("Google OAuth request failed error=#{error}", status: status)
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    Logger.warning("Google OAuth request failed", status: status)
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("Google OAuth request failed")
    {:error, reason}
  end

  def exchange_device_code_for_token(device_code) do
    with {:ok, {client_id, client_secret}} <- get_env() do
      body = %{
        client_id: client_id,
        client_secret: client_secret,
        device_code: device_code,
        grant_type: "urn:ietf:params:oauth:grant-type:device_code"
      }

      "/token"
      |> build_request()
      |> Req.post(form: body)
      |> handle_response()
    end
  end

  defp get_env do
    with {:ok, client_id} <- fetch_config(:google_oauth_client_id),
         {:ok, client_secret} <- fetch_config(:google_oauth_client_secret) do
      {:ok, {client_id, client_secret}}
    end
  end

  defp fetch_config(key) do
    case Application.fetch_env(:save_it, key) do
      {:ok, value} when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, {:missing_config, key}}
        else
          {:ok, value}
        end

      _ ->
        {:error, {:missing_config, key}}
    end
  end

  defp build_request(path) do
    req_options =
      :save_it
      |> Application.get_env(:google_oauth_req_options, [])
      |> Keyword.put_new(
        :base_url,
        Application.get_env(:save_it, :google_oauth_api_url, @google_oauth_api_url)
      )
      |> Keyword.put_new(:retry, false)
      |> Keyword.put(:url, path)

    Req.new(req_options)
  end
end
