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

  def async_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    Task.async(fn -> deliver_downloaded_file(context, file) end)
  end

  def async_downloaded_files(%DownloadContext{} = context, files) when is_list(files) do
    Task.async(fn -> deliver_downloaded_files(context, files) end)
  end

  def deliver_cached_file(%DownloadContext{} = context, file_path) when is_binary(file_path) do
    file_path
    |> send_cached_file(context)
    |> to_outcome()
  end

  def deliver_cached_files(%DownloadContext{} = context, file_paths) when is_list(file_paths) do
    file_paths
    |> send_cached_files(context)
    |> to_outcome()
  end

  defp deliver_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    case send_downloaded_file(context, file) do
      :ok ->
        FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
        ok()

      {:error, reason} ->
        error(reason)
    end
  end

  defp deliver_downloaded_files(%DownloadContext{} = context, files) do
    case send_downloaded_files(context, files) do
      :ok ->
        FileHelper.write_folder(context.purge_url, files)
        ok()

      {:error, reason} ->
        error(reason)
    end
  end

  defp send_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    safe_send_result(fn ->
      send_downloaded_file(context.chat_id, file,
        source_url: context.original_url,
        report_too_large: false
      )
    end)
  end

  defp send_downloaded_files(%DownloadContext{} = context, files) do
    safe_send_result(fn ->
      send_files(context.chat_id, files,
        source_url: context.original_url,
        report_too_large: false
      )
    end)
  end

  defp send_cached_file(file_path, %DownloadContext{} = context) do
    safe_send_result(fn ->
      send_file(context.chat_id, file_path, {:file, file_path},
        source_url: context.original_url,
        download_url: context.download_url,
        report_too_large: false
      )
    end)
  end

  defp send_cached_files(file_paths, %DownloadContext{} = context) do
    safe_send_result(fn ->
      send_filenames(context.chat_id, file_paths,
        source_url: context.original_url,
        report_too_large: false
      )
    end)
  end

  defp to_outcome(:ok), do: ok()
  defp to_outcome({:error, reason}), do: error(reason)

  defp ok do
    %{channel: :telegram, status: :ok, error_messages: []}
  end

  defp error(reason) do
    %{channel: :telegram, status: :error, error_messages: [error_message(reason)]}
  end

  defp error_message(:telegram_file_too_large), do: error_message(@telegram_file_too_large_reason)
  defp error_message(reason), do: "Send to telegram failed, #{format_error_reason(reason)}"

  defp send_files(chat_id, files, opts) do
    source_url = Keyword.get(opts, :source_url)
    report_too_large = Keyword.get(opts, :report_too_large, true)

    if all_images?(files) and length(files) > 1 do
      send_media_group(
        chat_id,
        Enum.map(files, fn %DownloadedFile{} = file ->
          {file.file_name, {:file_content, file.file_content, file.file_name}, source_url,
           file.download_url}
        end)
      )
    else
      send_each(files, fn %DownloadedFile{} = file ->
        send_downloaded_file(chat_id, file,
          source_url: source_url,
          report_too_large: report_too_large
        )
      end)
    end
  end

  defp send_downloaded_file(chat_id, %DownloadedFile{} = file, opts) do
    send_file(
      chat_id,
      file.file_name,
      {:file_content, file.file_content, file.file_name},
      Keyword.put_new(opts, :download_url, file.download_url)
    )
  end

  defp send_filenames(chat_id, filenames, opts) do
    source_url = Keyword.get(opts, :source_url)
    report_too_large = Keyword.get(opts, :report_too_large, true)

    if all_images?(filenames) and length(filenames) > 1 do
      send_media_group(
        chat_id,
        Enum.map(filenames, fn filename -> {filename, {:file, filename}, source_url} end)
      )
    else
      send_each(filenames, fn filename ->
        send_file(chat_id, filename, {:file, filename},
          source_url: source_url,
          report_too_large: report_too_large
        )
      end)
    end
  end

  defp send_media_group(chat_id, files) do
    case Telegram.send_media_group(chat_id, files) do
      {:ok, messages} ->
        files
        |> Enum.zip(messages)
        |> send_each(&index_media_group_photo(chat_id, &1))

      {:error, reason} ->
        Logger.error("Failed to send media group: #{inspect(reason)}")
        send_media_group_files_individually(chat_id, files)
    end
  end

  defp send_media_group_files_individually(chat_id, files) do
    send_each(files, fn
      {file_name, content, source_url, download_url} ->
        send_file(chat_id, file_name, content,
          source_url: source_url,
          download_url: download_url,
          report_too_large: false
        )

      {file_name, content, source_url} ->
        send_file(chat_id, file_name, content,
          source_url: source_url,
          report_too_large: false
        )

      {file_name, content} ->
        send_file(chat_id, file_name, content, report_too_large: false)
    end)
  end

  defp index_media_group_photo(chat_id, {{_file_name, content, source_url, download_url}, msg}) do
    index_photo(chat_id, content, msg, url: source_url, download_url: download_url)
  end

  defp index_media_group_photo(chat_id, {{_file_name, content, source_url}, msg}) do
    index_photo(chat_id, content, msg, url: source_url)
  end

  defp index_media_group_photo(chat_id, {{_file_name, content}, msg}) do
    index_photo(chat_id, content, msg)
  end

  defp index_photo(chat_id, content, msg, attrs \\ []) do
    file_id = get_file_id(msg)
    image_base64 = encode_file_content(content)

    attrs =
      attrs
      |> Keyword.put(:image, image_base64)
      |> Keyword.put_new(:caption, "")
      |> Keyword.put(:file_id, file_id)
      |> Keyword.put(:belongs_to_id, chat_id)
      |> Map.new()

    safe_index_photo(attrs)
  end

  defp send_file(chat_id, file_name, file_content, opts) do
    content =
      case file_content do
        {:file, file} -> {:file, file}
        {:file_content, file_content, file_name} -> {:file_content, file_content, file_name}
      end

    caption = Keyword.get(opts, :caption, "")
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)
    report_too_large = Keyword.get(opts, :report_too_large, true)

    cond do
      telegram_upload_too_large?(content) ->
        if report_too_large do
          ExGram.send_message(chat_id, "💔 File is too large for Telegram Bot API upload.")
        end

        {:error, :telegram_file_too_large}

      true ->
        do_send_file(chat_id, file_name, content,
          caption: caption,
          source_url: source_url,
          download_url: download_url
        )
    end
  end

  defp do_send_file(chat_id, file_name, content, opts) do
    caption = Keyword.fetch!(opts, :caption)
    source_url = Keyword.get(opts, :source_url)
    download_url = Keyword.get(opts, :download_url)

    case file_extension(file_name) do
      ext when ext in [".png", ".jpg", ".jpeg"] ->
        with {:ok, msg} <-
               safe_send_result(fn -> ExGram.send_photo(chat_id, content, caption: caption) end) do
          index_photo(chat_id, content, msg,
            caption: caption,
            url: source_url,
            download_url: download_url
          )
        end

      ".mp4" ->
        normalize_send_result(
          safe_send_result(fn ->
            ExGram.send_video(chat_id, content, supports_streaming: true, caption: caption)
          end)
        )

      ".gif" ->
        normalize_send_result(
          safe_send_result(fn -> ExGram.send_animation(chat_id, content, caption: caption) end)
        )

      _ ->
        normalize_send_result(
          safe_send_result(fn -> ExGram.send_document(chat_id, content, caption: caption) end)
        )
    end
  end

  defp send_each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp safe_send_result(send_fun) do
    send_fun.()
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

  defp telegram_upload_too_large?({:file_content, file_content, _file_name}) do
    byte_size(file_content) > @telegram_upload_max_file_size
  end

  defp telegram_upload_too_large?({:file, file_path}) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size > @telegram_upload_max_file_size
      {:error, _reason} -> false
    end
  end

  defp file_extension(file_name) do
    Path.extname(file_name)
  end

  defp all_images?(files) when is_list(files) do
    Enum.all?(files, fn
      %DownloadedFile{file_name: file_name} ->
        image_file?(file_name)

      {file_name, _file_content, _source_url} ->
        image_file?(file_name)

      {file_name, _file_content} ->
        image_file?(file_name)

      file_name when is_binary(file_name) ->
        image_file?(file_name)
    end)
  end

  defp image_file?(file_name) do
    file_extension(file_name) in [".png", ".jpg", ".jpeg"]
  end

  defp encode_file_content({:file, file}) do
    File.read!(file) |> Base.encode64()
  end

  defp encode_file_content({:file_content, file_content, _file_name}) do
    Base.encode64(file_content)
  end

  defp get_file_id(msg) do
    photos =
      cond do
        is_map(msg) and Map.has_key?(msg, :photo) -> msg.photo
        is_map(msg) and Map.has_key?(msg, "photo") -> msg["photo"]
        true -> nil
      end

    case photos do
      [_ | _] = photos ->
        photo = List.last(photos)
        Map.get(photo, :file_id) || Map.get(photo, "file_id")

      _ ->
        Logger.error("No photo found in the message")
        nil
    end
  end

  defp safe_index_photo(photo_params) do
    PhotoService.create_photo!(photo_params)
    :ok
  rescue
    error ->
      Logger.error("Typesense create_photo failed: #{Exception.message(error)}")
      :error
  catch
    kind, reason ->
      Logger.error("Typesense create_photo failed: #{inspect({kind, reason})}")
      :error
  end

  defp format_error_reason(%{message: message}) when is_binary(message), do: message
  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_error_reason(reason), do: inspect(reason)
end
