defmodule SmallSdk.Telegram do
  require Logger

  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.telegram.org")

  def download_file_content(file_path) when is_binary(file_path) do
    bot_token = get_env()
    url = "/file/bot#{bot_token}/#{file_path}"

    case get(url) do
      {:ok, response} ->
        {:ok, response.body}

      {:error, error} ->
        {:error, error}
    end
  end

  def download_file_content!(file_path) when is_binary(file_path) do
    case download_file_content(file_path) do
      {:ok, body} -> body
      {:error, error} -> raise "Error: #{inspect(error)}"
    end
  end

  defp get_env() do
    bot_token = Application.fetch_env!(:save_it, :telegram_bot_token)

    bot_token
  end
end
