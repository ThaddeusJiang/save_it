defmodule AierBot.GoogleOAuth2DeviceFlow do
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://oauth2.googleapis.com")
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Headers, [
    {"Content-Type", "application/x-www-form-urlencoded"}
  ])

  @client_id System.fetch_env!("GOOGLE_OAUTH_CLIENT_ID")
  @client_secret System.fetch_env!("GOOGLE_OAUTH_CLIENT_SECRET")
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
    IO.puts("handle_response, body: #{inspect(body)}")
    {:ok, body}
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) do
    IO.puts("handle_response, status: #{status}, body: #{inspect(body)}")
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}) do
    IO.puts("handle_response, reason: #{inspect(reason)}")
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
