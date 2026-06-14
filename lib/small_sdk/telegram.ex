defmodule SmallSdk.Telegram do
  @moduledoc false

  require Logger

  @telegram_api_url "https://api.telegram.org"

  def send_media_group(chat_id, files, opts \\ []) when is_list(files) do
    token = get_env()
    path = "/bot#{token}/sendMediaGroup"
    caption = Keyword.get(opts, :caption, "")
    message_thread_id = Keyword.get(opts, :message_thread_id)

    {media_entries, file_fields} =
      files
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {file, index}, {media_acc, fields_acc} ->
        {_file_name, content} = media_group_file_parts(file)
        part_name = "media#{index}"

        media =
          %{
            type: "photo",
            media: "attach://#{part_name}"
          }
          |> put_caption(caption)

        field =
          case content do
            {:file, file_path} ->
              {part_name, File.stream!(file_path, 2048, [])}

            {:file_content, file_content, file_name} ->
              {part_name, {file_content, filename: file_name}}
          end

        {[media | media_acc], [field | fields_acc]}
      end)

    media_json = media_entries |> Enum.reverse() |> Jason.encode!()

    multipart_fields =
      [{"chat_id", to_string(chat_id)}]
      |> maybe_append_multipart_field("message_thread_id", message_thread_id)
      |> Kernel.++([{"media", media_json} | Enum.reverse(file_fields)])

    path
    |> build_request()
    |> Req.post(form_multipart: multipart_fields)
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        decode_send_media_group_body(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:telegram_http_error, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp put_caption(media, ""), do: media
  defp put_caption(media, nil), do: media
  defp put_caption(media, caption), do: Map.put(media, :caption, caption)

  defp maybe_append_multipart_field(fields, _name, nil), do: fields
  defp maybe_append_multipart_field(fields, name, value), do: fields ++ [{name, to_string(value)}]

  defp media_group_file_parts({file_name, content, _source_url, _download_url, _thumbnail_url}),
    do: {file_name, content}

  defp media_group_file_parts({file_name, content, _source_url, _download_url}),
    do: {file_name, content}

  defp media_group_file_parts({file_name, content, _source_url}), do: {file_name, content}
  defp media_group_file_parts({file_name, content}), do: {file_name, content}

  def download_file_content(file_path) when is_binary(file_path) do
    bot_token = get_env()
    url = "/file/bot#{bot_token}/#{file_path}"

    url
    |> build_request()
    |> Req.get()
    |> case do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:telegram_http_error, status, body}}

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

  defp get_env do
    bot_token = Application.fetch_env!(:save_it, :telegram_bot_token)

    bot_token
  end

  defp build_request(path) do
    req_options =
      :save_it
      |> Application.get_env(:telegram_req_options, [])
      |> Keyword.put_new(
        :base_url,
        Application.get_env(:save_it, :telegram_api_url, @telegram_api_url)
      )
      |> Keyword.put_new(:retry, false)
      |> Keyword.put(:url, path)

    Req.new(req_options)
  end
end
