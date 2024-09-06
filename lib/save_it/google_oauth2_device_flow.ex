defmodule SaveIt.GoogleOAuth2DeviceFlow do
  require Logger
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://oauth2.googleapis.com")
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Headers, [
    {"Content-Type", "application/x-www-form-urlencoded"}
  ])

  @client_id Application.compile_env(:save_it, :google_oauth_client_id)
  @client_secret Application.compile_env(:save_it, :google_oauth_client_secret)
  @device_code_url "/device/code"
  @token_url "/token"

  def get_device_code do
    body = %{
      client_id: @client_id,
      scope: "https://www.googleapis.com/auth/drive.file"
    }

    post(@device_code_url, body)
    |> handle_response()
  end

  defp handle_response({:ok, %Tesla.Env{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) do
    Logger.warning("handle_response, status: #{status}, body: #{inspect(body)}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    Logger.error("handle_response, reason: #{inspect(reason)}")
    {:error, reason}
  end

  def exchange_device_code_for_token(device_code) do
    body = %{
      client_id: @client_id,
      client_secret: @client_secret,
      device_code: device_code,
      grant_type: "urn:ietf:params:oauth:grant-type:device_code"
    }

    post(@token_url, body)
    |> handle_response()
  end
end
