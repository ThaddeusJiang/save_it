defmodule SaveIt.TelegramDelivery do
  @moduledoc false

  require Logger

  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.PhotoService
  alias SmallSdk.Telegram

  @telegram_upload_max_file_size 50 * 1024 * 1024
  @telegram_file_too_large_reason "file is too large for Telegram Bot API upload."

  defmodule Item do
    @enforce_keys [:file_name, :content]
    defstruct [:file_name, :content, caption: "", url: nil, download_url: nil]
  end

  def async_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    Task.async(fn ->
      deliver_items(
        context.chat_id,
        [downloaded_item(file, context)],
        fn -> FileHelper.write_file(file.file_name, file.file_content, context.cache_url) end
      )
    end)
  end

  def async_downloaded_files(%DownloadContext{} = context, files) when is_list(files) do
    Task.async(fn ->
      items = Enum.map(files, &downloaded_item(&1, context))

      deliver_items(context.chat_id, items, fn ->
        FileHelper.write_folder(context.purge_url, files)
      end)
    end)
  end

  def deliver_cached_file(%DownloadContext{} = context, file_path) when is_binary(file_path) do
    deliver_items(context.chat_id, [cached_item(file_path, context)], fn -> :ok end)
  end

  def deliver_cached_files(%DownloadContext{} = context, file_paths) when is_list(file_paths) do
    items = Enum.map(file_paths, &cached_item(&1, context))
    deliver_items(context.chat_id, items, fn -> :ok end)
  end

  defp deliver_items(chat_id, items, on_success) do
    case safely(fn -> send_items(chat_id, items) end) do
      :ok ->
        on_success.()
        ok()

      {:error, reason} ->
        error(reason)
    end
  end

  defp downloaded_item(%DownloadedFile{} = file, %DownloadContext{} = context) do
    %Item{
      file_name: file.file_name,
      content: {:file_content, file.file_content, file.file_name},
      url: context.original_url,
      download_url: file.download_url
    }
  end

  defp cached_item(file_path, %DownloadContext{} = context) do
    %Item{
      file_name: file_path,
      content: {:file, file_path},
      url: context.original_url,
      download_url: context.download_url
    }
  end

  defp send_items(chat_id, items) do
    if media_group?(items) do
      send_media_group(chat_id, items)
    else
      send_each(items, &send_item(chat_id, &1))
    end
  end

  defp media_group?(items) do
    length(items) > 1 and Enum.all?(items, &image_item?/1)
  end

  defp send_media_group(chat_id, items) do
    case Telegram.send_media_group(chat_id, Enum.map(items, &media_group_entry/1)) do
      {:ok, messages} ->
        items
        |> Enum.zip(messages)
        |> send_each(fn {item, message} -> index_item(chat_id, item, message) end)

      {:error, reason} ->
        Logger.error("Failed to send media group: #{inspect(reason)}")
        send_each(items, &send_item(chat_id, &1))
    end
  end

  defp media_group_entry(%Item{
         file_name: file_name,
         content: content,
         url: url,
         download_url: nil
       }) do
    {file_name, content, url}
  end

  defp media_group_entry(%Item{
         file_name: file_name,
         content: content,
         url: url,
         download_url: download_url
       }) do
    {file_name, content, url, download_url}
  end

  defp send_item(chat_id, %Item{} = item) do
    if telegram_upload_too_large?(item.content) do
      {:error, :telegram_file_too_large}
    else
      do_send_item(chat_id, item)
    end
  end

  defp do_send_item(
         chat_id,
         %Item{file_name: file_name, content: content, caption: caption} = item
       ) do
    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        with {:ok, message} <-
               safely(fn -> ExGram.send_photo(chat_id, content, caption: caption) end),
             :ok <- index_item(chat_id, item, message) do
          :ok
        end

      ".mp4" ->
        normalize_send_result(
          safely(fn ->
            ExGram.send_video(chat_id, content, supports_streaming: true, caption: caption)
          end)
        )

      ".gif" ->
        normalize_send_result(
          safely(fn -> ExGram.send_animation(chat_id, content, caption: caption) end)
        )

      _ ->
        normalize_send_result(
          safely(fn -> ExGram.send_document(chat_id, content, caption: caption) end)
        )
    end
  end

  defp index_item(chat_id, %Item{} = item, message) do
    message
    |> photo_params(chat_id, item)
    |> index_photo()
  end

  defp photo_params(message, chat_id, %Item{} = item) do
    %{
      image: encode_file_content(item.content),
      caption: item.caption,
      file_id: get_file_id(message),
      belongs_to_id: chat_id
    }
    |> maybe_put(:url, item.url)
    |> maybe_put(:download_url, item.download_url)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp index_photo(photo_params) do
    PhotoService.create_photo!(photo_params)
    :ok
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      :ok
  catch
    kind, reason ->
      Logger.error("Typesense create_photo failed: #{inspect({kind, reason})}")
      :ok
  end

  defp send_each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp safely(fun) do
    fun.()
  rescue
    error ->
      Logger.error("Failed to send file to Telegram: #{Exception.message(error)}")
      {:error, error}
  catch
    kind, reason ->
      Logger.error("Failed to send file to Telegram: #{inspect({kind, reason})}")
      {:error, reason}
  end

  defp normalize_send_result({:ok, _message}), do: :ok
  defp normalize_send_result({:error, reason}), do: {:error, reason}

  defp ok do
    %{channel: :telegram, status: :ok, error_messages: []}
  end

  defp error(reason) do
    %{channel: :telegram, status: :error, error_messages: [error_message(reason)]}
  end

  defp error_message(:telegram_file_too_large), do: error_message(@telegram_file_too_large_reason)
  defp error_message(reason), do: "Send to telegram failed, #{format_error_reason(reason)}"

  defp telegram_upload_too_large?({:file_content, file_content, _file_name}) do
    byte_size(file_content) > @telegram_upload_max_file_size
  end

  defp telegram_upload_too_large?({:file, file_path}) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size > @telegram_upload_max_file_size
      {:error, _reason} -> false
    end
  end

  defp image_item?(%Item{file_name: file_name}) do
    file_extension(file_name) in [".png", ".jpg", ".jpeg"]
  end

  defp file_extension(file_name) do
    Path.extname(file_name)
  end

  defp encode_file_content({:file, file}) do
    File.read!(file) |> Base.encode64()
  end

  defp encode_file_content({:file_content, file_content, _file_name}) do
    Base.encode64(file_content)
  end

  defp get_file_id(message) do
    photos =
      cond do
        is_map(message) and Map.has_key?(message, :photo) -> message.photo
        is_map(message) and Map.has_key?(message, "photo") -> message["photo"]
        true -> nil
      end

    case photos do
      [_ | _] = photo_sizes ->
        photo_sizes
        |> List.last()
        |> then(&(Map.get(&1, :file_id) || Map.get(&1, "file_id")))

      _ ->
        Logger.error("No photo found in the message")
        nil
    end
  end

  defp format_error_reason(%{message: message}) when is_binary(message), do: message
  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_error_reason(reason), do: inspect(reason)
end
