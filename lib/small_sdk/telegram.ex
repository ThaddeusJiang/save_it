defmodule SmallSdk.Telegram do
  require Logger

  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.telegram.org")

  def send_media_group(chat_id, files) when is_list(files) do
    token = get_env()
    path = "/bot#{token}/sendMediaGroup"

    {media_entries, multipart} =
      files
      |> Enum.with_index()
      |> Enum.reduce({[], Tesla.Multipart.new()}, fn {{_file_name, content}, index}, {media_acc, mp} ->
        part_name = "media#{index}"

        media = %{
          type: "photo",
          media: "attach://#{part_name}"
        }

        mp =
          case content do
            {:file, file_path} ->
              Tesla.Multipart.add_file(mp, file_path, name: part_name)

            {:file_content, file_content, file_name} ->
              Tesla.Multipart.add_file_content(mp, file_content, file_name, name: part_name)
          end

        {[media | media_acc], mp}
      end)

    media_json = media_entries |> Enum.reverse() |> Jason.encode!()

    multipart =
      multipart
      |> Tesla.Multipart.add_field("chat_id", to_string(chat_id))
      |> Tesla.Multipart.add_field("media", media_json)

    case post(path, multipart, headers: Tesla.Multipart.headers(multipart)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        decode_send_media_group_body(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:telegram_http_error, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

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

  defp decode_send_media_group_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true, "result" => result}} ->
        {:ok, result}

      {:ok, decoded} ->
        {:error, {:telegram_api_error, decoded}}

      {:error, reason} ->
        {:error, {:invalid_json_response, reason}}
    end
  end

  defp decode_send_media_group_body(%{"ok" => true, "result" => result}), do: {:ok, result}
  defp decode_send_media_group_body(body), do: {:error, {:telegram_api_error, body}}

  defp get_env() do
    bot_token = Application.fetch_env!(:save_it, :telegram_bot_token)

    bot_token
  end
end
