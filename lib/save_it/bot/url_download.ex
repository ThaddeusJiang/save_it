defmodule SaveIt.Bot.UrlDownload do
  @moduledoc false

  require Logger

  import SaveIt.Bot.MapHelper, only: [put_optional_keyword: 3]
  import SaveIt.SmallHelper.UrlHelper, only: [direct_media_url?: 1]

  alias SaveIt.Bot.FileType
  alias SaveIt.Bot.LogFormat
  alias SaveIt.Bot.MediaSender
  alias SaveIt.Bot.MessageInfo
  alias SaveIt.Bot.ThumbnailDownload
  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.FileHelper
  alias SaveIt.GoogleDrive
  alias SaveIt.Telegram
  alias SaveIt.UrlMetadata
  alias SmallSdk.BadNews
  alias SmallSdk.Cobalt
  alias SmallSdk.HlsDownloader
  alias SmallSdk.LinkPreview
  alias SmallSdk.WebDownloader

  @progress [
    "Searching 🔎",
    "Downloading 💦",
    "Uploading 💭",
    "Have fun! 🎉"
  ]

  def handle_text_urls(text, %{chat: chat, message_id: message_id} = message, urls) do
    message = Map.put_new(message, :text, text)

    has_success? =
      urls
      |> Enum.map(&process_url(chat, &1, message))
      |> Enum.any?(&(&1 == :ok))

    if has_success? do
      Telegram.delete_message(chat.id, message_id)
    end
  end

  defp process_url(chat, url, message), do: process_url(chat, url, message, 0)

  defp process_url(chat, url, message, retry_attempt) do
    chat_id = chat.id

    Logger.debug("URL processing started chat_id=#{chat_id} source_url=#{LogFormat.url(url)}")

    case Telegram.send_message(chat_id, Enum.at(@progress, 0), on_rate_limit: :return) do
      {:ok, progress_message} ->
        continue_process_url(chat, url, message, progress_message)

      {:error, {:telegram_rate_limited, retry_after}} ->
        handle_rate_limited_url_progress(chat, url, message, retry_after, retry_attempt)

      {:error, reason} ->
        Logger.warning(
          "URL processing stopped before progress message source_url=#{LogFormat.url(url)} " <>
            "reason=#{LogFormat.value(reason)}"
        )

        {:error, reason}
    end
  end

  defp handle_rate_limited_url_progress(chat, url, message, retry_after, retry_attempt) do
    Telegram.handle_progress_rate_limit(
      chat,
      message,
      retry_after,
      retry_attempt,
      fn next_attempt ->
        process_url(chat, url, message, next_attempt)
      end
    )
  end

  defp continue_process_url(chat, url, message, progress_message) do
    context = %DownloadContext{
      chat_id: chat.id,
      chat: chat,
      progress_message_id: progress_message.message_id,
      original_url: url,
      message: message
    }

    case resolve_download_url(url) do
      {:ok, m3u8_url, :hls} ->
        Logger.debug(
          "URL download resolved result=hls " <>
            "source_url=#{LogFormat.url(url)} download_url=#{LogFormat.url(m3u8_url)}"
        )

        handle_hls_download(%{context | cache_url: url, download_url: m3u8_url}, m3u8_url)

      {:ok, purge_url, download_urls} ->
        Logger.debug(
          "URL download resolved result=multi " <>
            "source_url=#{LogFormat.url(url)} file_count=#{length(download_urls)}"
        )

        handle_multi_file_download(%{context | purge_url: purge_url}, download_urls)

      {:ok, download_url} ->
        Logger.debug(
          "URL download resolved result=single " <>
            "source_url=#{LogFormat.url(url)} download_url=#{LogFormat.url(download_url)}"
        )

        handle_single_file_download(%{
          context
          | download_url: download_url,
            cache_url: download_url
        })

      {:error, reason} ->
        Logger.debug("URL download resolve failed source_url=#{LogFormat.url(url)}")
        handle_download_failure(context, "💔 Failed to get download URL.", reason)
    end
  end

  defp resolve_download_url(url) do
    case Application.get_env(:save_it, :download_url_resolver) do
      nil -> get_download_url(url)
      resolver -> resolver.get_download_url(url)
    end
  end

  defp get_download_url(url) do
    cond do
      direct_media_url?(url) ->
        {:ok, url}

      BadNews.bad_news_url?(url) ->
        BadNews.get_download_url(url)

      true ->
        Cobalt.get_download_url(url)
    end
  end

  defp handle_hls_download(%DownloadContext{} = context, m3u8_url) do
    update_progress(context, 0..1)

    case hls_downloader().download(m3u8_url) do
      {:ok, %DownloadedFile{} = file} ->
        Logger.debug(
          "URL HLS downloaded file_name=#{LogFormat.value(file.file_name)} " <>
            "download_url=#{LogFormat.url(context.download_url)}"
        )

        update_progress(context, 0..2)

        MediaSender.send_downloaded_file(context.chat_id, file, send_opts(context))

        finalize_single_download(context, file)

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading HLS video.", reason)
    end
  end

  defp hls_downloader do
    Application.get_env(:save_it, :hls_downloader, HlsDownloader)
  end

  defp handle_multi_file_download(%DownloadContext{} = context, download_urls) do
    case FileHelper.get_downloaded_files(context.purge_url) do
      nil ->
        download_and_store_files(context, download_urls)

      downloaded_files ->
        update_progress(context, 0..2)

        MediaSender.send_filenames(context.chat_id, downloaded_files, send_opts(context))

        Telegram.delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_files(%DownloadContext{} = context, download_urls) do
    update_progress(context, 0..1)

    case WebDownloader.download_files(download_urls) do
      {:ok, files} ->
        Logger.debug("URL files downloaded file_count=#{length(files)}")

        update_progress(context, 0..2)

        MediaSender.send_files(context.chat_id, files, send_opts(context))

        Telegram.delete_message(context.chat_id, context.progress_message_id)
        FileHelper.write_folder(context.purge_url, files)
        GoogleDrive.upload_files(context.chat_id, files)

        Logger.info("resource_created source=url_download file_count=#{length(files)}",
          ansi_color: :green
        )

        :ok

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading file.", reason)
    end
  end

  defp handle_single_file_download(%DownloadContext{} = context) do
    case FileHelper.get_downloaded_file(context.download_url) do
      nil ->
        download_and_store_file(context)

      downloaded_file ->
        update_progress(context, 0..2)

        MediaSender.send_file(
          context.chat_id,
          downloaded_file,
          {:file, downloaded_file},
          send_opts(context)
        )

        Telegram.delete_message(context.chat_id, context.progress_message_id)
        :ok
    end
  end

  defp download_and_store_file(%DownloadContext{} = context) do
    update_progress(context, 0..1)

    case WebDownloader.download_file(context.download_url) do
      {:ok, %DownloadedFile{} = file} ->
        Logger.debug(
          "URL file downloaded file_name=#{LogFormat.value(file.file_name)} " <>
            "download_url=#{LogFormat.url(context.download_url)}"
        )

        if FileType.url_download_media?(file.file_name) do
          update_progress(context, 0..2)

          MediaSender.send_downloaded_file(context.chat_id, file, send_opts(context))

          finalize_single_download(context, file)
        else
          handle_non_media_download(context)
        end

      {:error, reason} ->
        handle_download_failure(context, "💔 Failed downloading file.", reason)
    end
  end

  defp handle_non_media_download(%DownloadContext{} = context) do
    case fallback_thumbnail(context) do
      {:ok, %DownloadedFile{} = file, source} ->
        case source do
          :telegram_thumbnail ->
            Logger.warning("Saved Telegram thumbnail fallback after non-media URL download")

          :webpage_preview ->
            Logger.warning("Saved webpage preview fallback after non-media URL download")
        end

        save_thumbnail_fallback(context, file, source)

      {:error, _fallback_reasons} ->
        Logger.warning("No thumbnail fallback available after non-media URL download")

        Telegram.update_message(
          context.chat_id,
          context.progress_message_id,
          "💔 No image preview found."
        )

        :error
    end
  end

  defp handle_download_failure(%DownloadContext{} = context, failure_message, _failure_reason) do
    case fallback_thumbnail(context) do
      {:ok, %DownloadedFile{} = file, source} ->
        log_thumbnail_fallback_success(source)
        save_thumbnail_fallback(context, file, source)

      {:error, _fallback_reasons} ->
        Logger.warning("No thumbnail fallback available after link download failed")

        Telegram.update_message(context.chat_id, context.progress_message_id, failure_message)
        :error
    end
  end

  defp fallback_thumbnail(%DownloadContext{} = context) do
    case ThumbnailDownload.from_message(context.message) do
      {:ok, %DownloadedFile{} = file} ->
        {:ok, file, :telegram_thumbnail}

      {:error, telegram_reason} ->
        case download_webpage_preview(context) do
          {:ok, %DownloadedFile{} = file} ->
            {:ok, file, :webpage_preview}

          {:error, preview_reason} ->
            {:error, %{telegram_thumbnail: telegram_reason, webpage_preview: preview_reason}}
        end
    end
  end

  defp log_thumbnail_fallback_success(:telegram_thumbnail) do
    Logger.warning("Saved Telegram thumbnail fallback after link download failed")
  end

  defp log_thumbnail_fallback_success(:webpage_preview) do
    Logger.warning("Saved webpage preview fallback after link download failed")
  end

  defp save_thumbnail_fallback(%DownloadContext{} = context, %DownloadedFile{} = file, source) do
    update_progress(context, 0..2)

    MediaSender.send_downloaded_file(
      context.chat_id,
      file,
      context
      |> send_opts(store_thumbnail_url?: source == :webpage_preview)
      |> Keyword.put(:store_download_url?, false)
    )

    finalize_thumbnail_download(context, file)
  end

  defp download_webpage_preview(%DownloadContext{} = context) do
    context.message
    |> MessageInfo.link_preview_url()
    |> Kernel.||(context.original_url)
    |> LinkPreview.download_image()
  end

  defp update_progress(%DownloadContext{} = context, range) do
    Telegram.update_message(
      context.chat_id,
      context.progress_message_id,
      Enum.slice(@progress, range)
    )
  end

  defp send_opts(%DownloadContext{} = context, opts \\ []) do
    metadata = link_preview_metadata(context, opts)

    [
      source_url: context.original_url,
      source_chat: context.chat,
      caption: MessageInfo.user_text_caption(context.message)
    ]
    |> put_optional_keyword(:download_url, context.download_url)
    |> put_optional_keyword(:thumbnail_url, thumbnail_url_from_metadata(metadata, opts))
    |> put_optional_keyword(:title, metadata_title(metadata))
    |> put_optional_keyword(:description, metadata_description(metadata))
    |> put_optional_keyword(:keywords, metadata_keywords(metadata))
    |> put_optional_keyword(:message_thread_id, MessageInfo.message_thread_id(context.message))
  end

  defp link_preview_metadata(%DownloadContext{} = context, opts) do
    context
    |> link_preview_metadata_url(opts)
    |> fetch_link_preview_metadata()
  end

  defp link_preview_metadata_url(
         %DownloadContext{message: message, original_url: original_url},
         opts
       ) do
    preview_url = MessageInfo.link_preview_url(message)
    fetch_original? = MessageInfo.user_text_caption(message) == ""

    thumbnail_needs_metadata? = Keyword.get(opts, :store_thumbnail_url?, true)

    UrlMetadata.metadata_page_url(original_url, preview_url,
      fetch_original?: fetch_original? or thumbnail_needs_metadata?
    )
  end

  defp fetch_link_preview_metadata(preview_url) when is_binary(preview_url) do
    case LinkPreview.get_metadata(preview_url) do
      {:ok, metadata} -> metadata
      {:error, _reason} -> nil
    end
  end

  defp fetch_link_preview_metadata(_preview_url), do: nil

  defp thumbnail_url_from_metadata(metadata, opts) do
    if Keyword.get(opts, :store_thumbnail_url?, true) do
      metadata_image_url(metadata)
    end
  end

  defp metadata_image_url(%{image_url: image_url}) when is_binary(image_url) and image_url != "",
    do: image_url

  defp metadata_image_url(_metadata), do: nil

  defp metadata_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp metadata_title(_metadata), do: nil

  defp metadata_description(%{description: description})
       when is_binary(description) and description != "",
       do: description

  defp metadata_description(_metadata), do: nil

  defp metadata_keywords(%{keywords: [_ | _] = keywords}), do: keywords
  defp metadata_keywords(_metadata), do: nil

  defp finalize_thumbnail_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    Telegram.delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.original_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)

    Logger.info("resource_created source=thumbnail_fallback file_name=#{file.file_name}",
      ansi_color: :green
    )

    :ok
  end

  defp finalize_single_download(%DownloadContext{} = context, %DownloadedFile{} = file) do
    Telegram.delete_message(context.chat_id, context.progress_message_id)
    FileHelper.write_file(file.file_name, file.file_content, context.cache_url)
    GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)

    Logger.info("resource_created source=url_download file_name=#{file.file_name}",
      ansi_color: :green
    )

    :ok
  end
end
