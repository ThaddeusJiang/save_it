defmodule SaveIt.BotTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  import ExUnit.CaptureLog

  alias ExGram.Adapter.Test, as: ExGramTestAdapter
  alias SaveIt.Bot
  alias SaveIt.FileHelper

  setup %{tmp_dir: tmp_dir} do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    previous_ex_gram = Application.get_all_env(:ex_gram)
    previous_save_it = Application.get_all_env(:save_it)

    Application.put_env(:ex_gram, :adapter, ExGram.Adapter.Test)
    Application.put_env(:ex_gram, :token, "test-token")
    Application.put_env(:save_it, :cobalt_api_url, base_url)
    Application.put_env(:save_it, :google_api_url, "https://www.googleapis.com")
    Application.put_env(:save_it, :telegram_bot_token, "test-token")

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    Application.put_env(:save_it, :typesense_url, base_url)
    Application.put_env(:save_it, :typesense_api_key, "test-typesense-key")
    Application.put_env(:save_it, :timezone, System.get_env("TZ") || "Asia/Tokyo")
    Application.put_env(:save_it, :data_dir, tmp_dir)

    if Process.whereis(ExGram.Adapter.Test) do
      ExGramTestAdapter.clean()
    else
      start_supervised!(%{
        id: ExGram.Adapter.Test,
        start: {ExGram.Adapter.Test, :start_link, [[]]}
      })
    end

    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 10})
    ExGramTestAdapter.backdoor_request(:edit_message_text, %{message_id: 10})
    ExGramTestAdapter.backdoor_request(:delete_message, true)

    ExGramTestAdapter.backdoor_request(:send_photo, %{
      message_id: 20,
      photo: [%{file_id: "telegram-photo-file-id"}]
    })

    on_exit(fn ->
      if Process.whereis(ExGram.Adapter.Test) do
        ExGramTestAdapter.clean()
      end

      restore_env(:ex_gram, previous_ex_gram)
      restore_env(:save_it, previous_save_it)
    end)

    %{base_url: base_url}
  end

  test "about reports private chat status and bot privacy mode", _context do
    ExGramTestAdapter.backdoor_request(:get_me, %{
      id: 9_001,
      username: "save_it_bot",
      can_read_all_group_messages: false
    })

    message = %{
      chat: %{id: 12_345, type: "private"},
      message_id: 11
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :about, message}, nil)

    request_body = sent_message_body()

    assert request_body.chat_id == 12_345
    assert request_body.text =~ "Chat: dm"
    assert request_body.text =~ "Public: no"
    assert request_body.text =~ "Bot admin: n/a"
    assert request_body.text =~ "Privacy Mode: enabled"
  end

  test "about reports public group status and bot admin membership", _context do
    ExGramTestAdapter.backdoor_request(:get_me, %{
      id: 9_001,
      username: "save_it_bot",
      can_read_all_group_messages: true
    })

    ExGramTestAdapter.backdoor_request(:get_chat_member, fn body ->
      assert body == %{chat_id: -100_123, user_id: 9_001}
      %{status: "administrator", user: %{id: 9_001, is_bot: true}}
    end)

    message = %{
      chat: %{id: -100_123, type: "supergroup", username: "save_it_group"},
      message_id: 12
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :about, message}, nil)

    request_body = sent_message_body()

    assert request_body.chat_id == -100_123
    assert request_body.text =~ "Chat: group"
    assert request_body.text =~ "Public: yes"
    assert request_body.text =~ "Bot admin: yes"
    assert request_body.text =~ "Privacy Mode: disabled"
  end

  test "about reports private channel status and non-admin membership", _context do
    ExGramTestAdapter.backdoor_request(:get_me, %{
      id: 9_001,
      username: "save_it_bot",
      can_read_all_group_messages: false
    })

    ExGramTestAdapter.backdoor_request(:get_chat_member, fn body ->
      assert body == %{chat_id: -100_456, user_id: 9_001}
      %{status: "member", user: %{id: 9_001, is_bot: true}}
    end)

    message = %{
      chat: %{id: -100_456, type: "channel"},
      message_id: 13
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :about, message}, nil)

    request_body = sent_message_body()

    assert request_body.chat_id == -100_456
    assert request_body.text =~ "Chat: channel"
    assert request_body.text =~ "Public: no"
    assert request_body.text =~ "Bot admin: no"
    assert request_body.text =~ "Privacy Mode: enabled"
  end

  test "about reports unknown bot status when get me fails", _context do
    ExGramTestAdapter.backdoor_error(:get_me, "get me failed")

    message = %{
      chat: %{id: -100_789, type: "supergroup"},
      message_id: 14
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :about, message}, nil)

    request_body = sent_message_body()

    assert request_body.chat_id == -100_789
    assert request_body.text =~ "Bot admin: unknown"
    assert request_body.text =~ "Privacy Mode: unknown"
  end

  test "uses user text as the caption when indexing a downloaded URL photo", %{base_url: base_url} do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    message_text = "summer reference #{original_url}"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-original-url-test.jpg"
    cached_file_content = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    FileHelper.write_file(cached_file_name, cached_file_content, download_url)

    on_exit(fn ->
      cleanup_cached_file(download_url, cached_file_name)
    end)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 99,
      text: message_text
    }

    assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["caption"] == "summer reference"
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/20"

    assert Enum.any?(exgram_calls(), fn
             {:post, :send_photo, {:multipart, parts}} ->
               {"caption", "summer reference"} in parts and
                 not Enum.any?(parts, &match?({"show_caption_above_media", _}, &1))

             _ ->
               false
           end)
  end

  test "does not store a source message URL for private DM saves", %{base_url: base_url} do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    message_text = "dm reference #{original_url}"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-private-dm-source-url-test.jpg"
    cached_file_content = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    FileHelper.write_file(cached_file_name, cached_file_content, download_url)

    on_exit(fn ->
      cleanup_cached_file(download_url, cached_file_name)
    end)

    message = %{
      chat: %{id: 12_345, type: "private", username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 100,
      text: message_text
    }

    assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["caption"] == "dm reference"
    refute Map.has_key?(document, "source_message_id")
    refute Map.has_key?(document, "source_message_url")
  end

  test "uses the URL og description as the caption when user text only contains the URL", %{
    base_url: base_url
  } do
    original_url = base_url <> "/photo-page"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-og-description-test.jpg"
    cached_file_content = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    FileHelper.write_file(cached_file_name, cached_file_content, download_url)

    on_exit(fn ->
      cleanup_cached_file(download_url, cached_file_name)
    end)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 97
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
      end)

    refute log =~ "resource_created"
    refute log =~ "download_file started"
    refute log =~ "download_file succeeded"
    refute log =~ "File.write succeeded"
    refute log =~ "Link preview metadata fetched"
    refute log =~ "Link preview caption selected"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}
    assert_receive {:test_http_request, :get, "/photo-page", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/preview.jpg"
    assert document["caption"] == "Photo Page OG Description"
  end

  test "uses the x.com URL og description as the caption when user text only contains the URL",
       %{base_url: base_url} do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = base_url <> "/downloaded/photo.jpg"
    preview_url = base_url <> "/x-page"

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 98,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}
    assert_receive {:test_http_request, :get, "/x-page", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/preview.jpg"
    assert document["caption"] == "X Page OG Description"

    assert Enum.any?(exgram_calls(), fn
             {:post, :send_photo, {:multipart, parts}} ->
               {"caption", "X Page OG Description"} in parts

             _ ->
               false
           end)
  end

  test "sends downloaded URL media to the source topic and stores a topic message URL",
       %{base_url: base_url} do
    Application.put_env(:ex_gram, :adapter, __MODULE__.TopicSendPhotoAdapter)

    chat_id = -1_001_234_567_890
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = base_url <> "/downloaded/photo.jpg"
    preview_url = base_url <> "/x-page"

    message = %{
      chat: %{id: chat_id},
      date: 1_717_170_000,
      message_id: 99,
      message_thread_id: 42,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:exgram_request, :post, "/bottest-token/sendPhoto", {:multipart, parts}}
    assert multipart_part(parts, "chat_id") == Integer.to_string(chat_id)
    assert multipart_part(parts, "message_thread_id") == "42"
    assert multipart_part(parts, "caption") == "X Page OG Description"

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    refute Map.has_key?(document, "source_message_id")
    assert document["download_url"] == download_url
    assert document["source_message_url"] == "https://t.me/c/1234567890/42/77"
  end

  test "falls back to the x.com URL og title as caption without logging preview metadata by default",
       %{base_url: base_url} do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    preview_url = base_url <> "/x-title-only-page"

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 101,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
      end)

    refute log =~ "Link preview metadata fetched"
    refute log =~ "Link preview caption selected"
    assert log =~ "[info] resource_created"
    assert log =~ IO.ANSI.green()
    assert log =~ "source=url_download"
    refute log =~ "kind=resource"
    refute log =~ "[notice]"
    refute log =~ "download_file started"
    refute log =~ "download_file succeeded"
    refute log =~ "File.write succeeded"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}
    assert_receive {:test_http_request, :get, "/x-title-only-page", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["caption"] == "X Title Only Page OG Title"

    assert Enum.any?(exgram_calls(), fn
             {:post, :send_photo, {:multipart, parts}} ->
               {"caption", "X Title Only Page OG Title"} in parts

             _ ->
               false
           end)
  end

  test "logs link preview metadata fetch failures", %{base_url: base_url} do
    original_url = "https://x.com/example/status/1"
    preview_url = base_url <> "/missing-preview-page"

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 102,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
      end)

    assert log =~ "Link preview metadata fetch failed"
    assert log =~ "page_url=\"#{preview_url}\""
    assert log =~ "reason={:preview_page_status, 404}"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}
    assert_receive {:test_http_request, :get, "/downloaded/photo.jpg", ""}
    assert_receive {:test_http_request, :get, "/missing-preview-page", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == ""
    refute Map.has_key?(document, "thumbnail_url")
  end

  test "uses the youtube.com URL og title as the caption when user text only contains the URL",
       %{base_url: base_url} do
    original_url = "https://www.youtube.com/shorts/clip123"
    preview_url = base_url <> "/youtube-page"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoThumbnailAdapter)
    Application.put_env(:save_it, :video_metadata_probe, __MODULE__.VideoMetadataProbe)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 100,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}
    assert_receive {:test_http_request, :get, "/downloaded/video.mp4", ""}
    assert_receive {:test_http_request, :get, "/youtube-page", ""}

    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo", {:multipart, parts}}
    assert multipart_part(parts, "caption") == "YouTube Page OG Title"

    assert_receive {:exgram_request, :get, "/bottest-token/getFile",
                    %{file_id: "sent-video-thumbnail-id"}}

    assert_receive {:telegram_download_request, _telegram_env}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["caption"] == "YouTube Page OG Title"

    assert_storage_file_with_uuidv7_extension(".mp4")
  end

  test "stores the Telegram thumbnail when a user-sent url cannot be resolved", _context do
    original_url = "https://example.com/unavailable"

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "link-thumbnail-file-id",
      file_path: "photos/link-thumbnail.jpg"
    })

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      message_id: 101,
      photo: [
        %{file_id: "small-link-thumbnail-file-id"},
        %{file_id: "link-thumbnail-file-id"}
      ]
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
      end)

    assert log =~ "Saved Telegram thumbnail fallback after link download failed"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}

    assert_receive {:telegram_download_request, telegram_env}

    assert telegram_env.url
           |> URI.to_string()
           |> String.ends_with?("/file/bottest-token/photos/link-thumbnail.jpg")

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    refute Map.has_key?(document, "download_url")
    refute Map.has_key?(document, "thumbnail_url")
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/20"

    refute Enum.any?(exgram_calls(), fn
             {:post, _path, %{text: text}} when is_binary(text) ->
               String.contains?(text, "Failed")

             _ ->
               false
           end)
  end

  test "stores the webpage preview image when Telegram does not include thumbnail media", %{
    base_url: base_url
  } do
    original_url = base_url <> "/preview-page"

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 102,
      text: original_url,
      entities: [%{offset: 0, type: "url", length: String.length(original_url)}],
      link_preview_options: %{url: original_url}
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
      end)

    assert log =~ "Saved webpage preview fallback after link download failed"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}

    assert_receive {:test_http_request, :get, "/preview-page", ""}
    assert_receive {:test_http_request, :get, "/preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    refute Map.has_key?(document, "download_url")
    assert document["thumbnail_url"] == base_url <> "/preview.jpg"
    assert document["caption"] == "Preview Page OG Description"
    assert document["file_id"] == "telegram-photo-file-id"
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/20"

    refute Enum.any?(exgram_calls(), fn
             {:post, _path, %{text: text}} when is_binary(text) ->
               String.contains?(text, "Failed")

             _ ->
               false
           end)
  end

  test "indexes a downloaded URL video using a generated cover before Telegram and webpage previews",
       %{base_url: base_url} do
    original_url = base_url <> "/video-page-with-telegram-thumbnail"
    download_url = base_url <> "/downloaded/video.mp4"
    message_text = "clip notes #{original_url}"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoThumbnailAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    Application.put_env(:save_it, :video_metadata_probe, __MODULE__.VideoMetadataProbe)
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.VideoCoverGenerator)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 103,
      text: message_text,
      link_preview_options: %{url: original_url}
    }

    assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}

    assert_receive {:test_http_request, :get, "/downloaded/video.mp4", ""}

    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo", {:multipart, parts}}
    assert multipart_part(parts, "chat_id") == "12345"
    assert multipart_part(parts, "caption") == "clip notes"
    assert multipart_part(parts, "supports_streaming") == "true"
    assert multipart_part(parts, "width") == "1080"
    assert multipart_part(parts, "height") == "1920"
    assert multipart_part(parts, "duration") == "12"
    assert multipart_part(parts, "thumbnail") == :file_content
    assert multipart_file_content(parts, "thumbnail") == test_video_cover()
    assert multipart_part(parts, "cover") == :file_content
    assert multipart_file_content(parts, "cover") == test_video_cover()

    refute_receive {:telegram_download_request, _telegram_env}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    refute Map.has_key?(document, "thumbnail_url")
    assert document["caption"] == "clip notes"
    assert document["file_id"] == "sent-video-file-id"
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_video_cover())
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/70"

    assert_receive {:test_http_request, :get, "/video-page-with-telegram-thumbnail", ""}
    refute_receive {:test_http_request, :get, "/video-preview.jpg", ""}
    refute_receive {:test_http_request, :get, "/preview.jpg", ""}

    assert_storage_file_with_uuidv7_extension(".mp4")
    assert_storage_file_content_with_uuidv7_extension(".jpg", test_video_cover())
  end

  test "falls back to the Telegram video thumbnail when generated cover is unavailable",
       %{base_url: base_url} do
    original_url = base_url <> "/video-page-with-telegram-thumbnail"
    download_url = base_url <> "/downloaded/video.mp4"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoThumbnailAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    Application.put_env(:save_it, :video_metadata_probe, __MODULE__.VideoMetadataProbe)
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.FailingVideoCoverGenerator)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 104,
      text: original_url,
      link_preview_options: %{url: original_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :get, "/downloaded/video.mp4", ""}
    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo", {:multipart, parts}}

    refute multipart_part(parts, "thumbnail")
    refute multipart_part(parts, "cover")

    assert_receive {:telegram_download_request, telegram_env}

    assert telegram_env.url
           |> URI.to_string()
           |> String.ends_with?("/file/bottest-token/video_thumbnails/sent.jpg")

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/video-preview.jpg"
    assert document["file_id"] == "sent-video-file-id"
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_jpeg())
  end

  test "indexes a downloaded video using the webpage preview when Telegram has no thumbnail", %{
    base_url: base_url
  } do
    original_url = base_url <> "/video-page"
    download_url = base_url <> "/downloaded/video.mp4"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoWithoutThumbnailAdapter)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 104,
      link_preview_options: %{url: original_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}

    assert_receive {:test_http_request, :get, "/downloaded/video.mp4", ""}

    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo", {:multipart, parts}}
    assert multipart_part(parts, "chat_id") == "12345"
    assert multipart_part(parts, "caption") == "Video Page OG Description"
    assert multipart_part(parts, "supports_streaming") == "true"

    assert_receive {:test_http_request, :get, "/video-page", ""}
    assert_receive {:test_http_request, :get, "/video-preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/video-preview.jpg"
    assert document["caption"] == "Video Page OG Description"
    assert document["file_id"] == "sent-video-file-id"
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_og_jpeg())
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/71"

    assert_storage_file_content_with_uuidv7_extension(".jpg", test_og_jpeg())
  end

  test "stores the webpage preview for a downloaded HLS URL video", %{base_url: base_url} do
    original_url = base_url <> "/hls-video-page"

    Application.put_env(:save_it, :download_url_resolver, __MODULE__.HlsDownloadUrlResolver)
    Application.put_env(:save_it, :hls_downloader, __MODULE__.HlsDownloaderAdapter)
    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoWithoutThumbnailAdapter)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 105,
      link_preview_options: %{url: original_url}
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo", {:multipart, parts}}
    assert multipart_part(parts, "chat_id") == "12345"
    assert multipart_part(parts, "caption") == "HLS Video Page OG Description"
    assert multipart_part(parts, "supports_streaming") == "true"

    assert_receive {:test_http_request, :get, "/hls-video-page", ""}
    assert_receive {:test_http_request, :get, "/video-preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == "https://stream.example/master.m3u8"
    assert document["thumbnail_url"] == base_url <> "/video-preview.jpg"
    assert document["caption"] == "HLS Video Page OG Description"
    assert document["file_id"] == "sent-video-file-id"
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_og_jpeg())

    assert_storage_file_content_with_uuidv7_extension(".jpg", test_og_jpeg())
  end

  test "stores the original user-sent url for every photo in a multi-image download", %{
    base_url: base_url
  } do
    original_url = "https://x.com/JennerItGirls/status/2057529104535023815?s=20"
    message_text = "runway gallery #{original_url}"
    purge_url = "https://x.com/JennerItGirls/status/2057529104535023815"

    cleanup_cached_folder(purge_url)

    on_exit(fn ->
      cleanup_cached_folder(purge_url)
    end)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramMediaGroupAdapter.request/1
    )

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_200_000,
      message_id: 100,
      text: message_text
    }

    assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}

    assert Jason.decode!(cobalt_body) == %{
             "url" => "https://x.com/JennerItGirls/status/2057529104535023815"
           }

    assert_receive {:telegram_media_group_request, conn}

    media =
      conn.body
      |> multipart_field("media")
      |> Jason.decode!()

    assert Enum.map(media, & &1["caption"]) == List.duplicate("runway gallery", 4)
    refute Enum.any?(media, &Map.has_key?(&1, "show_caption_above_media"))

    documents =
      Enum.map(1..4, fn _ ->
        assert_receive {:test_http_request, :post, "/collections/photos/documents",
                        typesense_body}

        Jason.decode!(typesense_body)
      end)

    assert Enum.map(documents, & &1["url"]) == List.duplicate(original_url, 4)
    assert Enum.map(documents, & &1["caption"]) == List.duplicate("runway gallery", 4)

    assert documents
           |> Enum.map(& &1["download_url"])
           |> Enum.sort() == [
             base_url <> "/downloaded/photo-1.jpg",
             base_url <> "/downloaded/photo-2.jpg",
             base_url <> "/downloaded/photo-3.jpg",
             base_url <> "/downloaded/photo-4.jpg"
           ]

    assert Enum.map(documents, & &1["file_id"]) == [
             "group-file-1",
             "group-file-2",
             "group-file-3",
             "group-file-4"
           ]

    refute Enum.any?(documents, &Map.has_key?(&1, "source_message_id"))

    assert Enum.map(documents, & &1["source_message_url"]) == [
             "https://t.me/save_it_test_chat/101",
             "https://t.me/save_it_test_chat/102",
             "https://t.me/save_it_test_chat/103",
             "https://t.me/save_it_test_chat/104"
           ]
  end

  test "handles /similar command attached to a photo", _context do
    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 29})

    ExGramTestAdapter.backdoor_request(:send_media_group, [
      %{message_id: 30},
      %{message_id: 31}
    ])

    message = %{
      chat: %{id: 12_354},
      text: nil,
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:command, :similar, message}, nil)

    calls = exgram_calls()

    assert {:post, :send_message, %{chat_id: 12_354, text: "Similar photos found."}} in calls

    assert Enum.any?(calls, fn
             {:post, :send_media_group, %{chat_id: 12_354}} -> true
             _ -> false
           end)
  end

  test "announces similar photos and sends multiple results as one media group", _context do
    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 30})

    ExGramTestAdapter.backdoor_request(:send_media_group, [
      %{message_id: 31},
      %{message_id: 32}
    ])

    message = %{
      chat: %{id: 12_345},
      caption: "/similar",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:message, message}, nil)

    calls = exgram_calls()

    assert {:post, :send_message, %{chat_id: 12_345, text: "Similar photos found."}} in calls

    media_group_calls =
      Enum.filter(calls, fn
        {:post, :send_media_group, _body} -> true
        _ -> false
      end)

    assert [
             {:post, :send_media_group, %{chat_id: 12_345, media: media}}
           ] = media_group_calls

    assert Enum.map(media, & &1.media) == ["similar-file-1", "similar-file-2"]
    assert Enum.map(media, & &1.caption) == ["first similar", "second similar"]
    refute Enum.any?(media, &Map.has_key?(&1, :show_caption_above_media))
  end

  test "announces similar photos and sends one result as one photo", _context do
    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 40})

    ExGramTestAdapter.backdoor_request(:send_photo, %{
      message_id: 41,
      photo: [%{file_id: "single-similar-file"}]
    })

    message = %{
      chat: %{id: 12_346},
      caption: "/similar",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:message, message}, nil)

    calls = exgram_calls()

    assert {:post, :send_message, %{chat_id: 12_346, text: "Similar photos found."}} in calls

    assert Enum.any?(calls, fn
             {:post, :send_photo,
              %{
                chat_id: 12_346,
                photo: "single-similar-file",
                caption: "single similar"
              } = body} ->
               not Map.has_key?(body, :show_caption_above_media)

             _ ->
               false
           end)

    refute Enum.any?(calls, fn
             {:post, :send_media_group, _body} -> true
             _ -> false
           end)
  end

  test "does not return the just uploaded photo as a similar result", _context do
    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 42})

    ExGramTestAdapter.backdoor_request(:send_photo, %{
      message_id: 43,
      photo: [%{file_id: "other-similar-file"}]
    })

    ExGramTestAdapter.backdoor_request(:send_media_group, [
      %{message_id: 44},
      %{message_id: 45}
    ])

    message = %{
      chat: %{id: 12_353},
      caption: "/similar",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:message, message}, nil)

    calls = exgram_calls()

    assert {:post, :send_message, %{chat_id: 12_353, text: "Similar photos found."}} in calls

    assert Enum.any?(calls, fn
             {:post, :send_photo,
              %{chat_id: 12_353, photo: "other-similar-file", caption: "other similar"}} ->
               true

             _ ->
               false
           end)

    refute Enum.any?(calls, fn
             {:post, :send_photo, %{photo: "uploaded-photo-file-id"}} -> true
             {:post, :send_media_group, _body} -> true
             _ -> false
           end)
  end

  test "silently skips similar photos that Telegram cannot send after media group failure",
       _context do
    Application.put_env(:ex_gram, :adapter, __MODULE__.SimilarMediaFailureAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    message = %{
      chat: %{id: 12_351},
      caption: "/similar",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:message, message}, nil)

    assert_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_351, text: "Similar photos found."}}

    assert_receive {:exgram_request, :post, "/bottest-token/sendMediaGroup", %{chat_id: 12_351}}

    assert_receive {:exgram_request, :post, "/bottest-token/sendPhoto",
                    %{chat_id: 12_351, photo: "broken-similar-file"}}

    assert_receive {:exgram_request, :post, "/bottest-token/sendPhoto",
                    %{chat_id: 12_351, photo: "sendable-similar-file"}}

    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_351, text: "Failed to send photos."}}
  end

  test "silently skips a single similar photo that Telegram cannot send", _context do
    Application.put_env(:ex_gram, :adapter, __MODULE__.SimilarMediaFailureAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDownloadAdapter.request/1
    )

    message = %{
      chat: %{id: 12_352},
      caption: "/similar",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    assert :ok = Bot.handle({:message, message}, nil)

    assert_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_352, text: "Similar photos found."}}

    assert_receive {:exgram_request, :post, "/bottest-token/sendPhoto",
                    %{chat_id: 12_352, photo: "broken-single-similar-file"}}

    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: 12_352, text: "Failed to send photos."}}
  end

  test "stores a directly uploaded photo in Typesense and Google Drive", _context do
    chat_id = 12_348
    stored_file_path = storage_file_path("direct-photo.jpg")

    File.rm(stored_file_path)
    configure_google_drive(chat_id)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.GoogleDriveAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/direct-photo.jpg"
    })

    message = %{
      chat: %{id: chat_id, username: "save_it_directs"},
      message_id: 321,
      caption: "direct image",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    Bot.handle({:message, message}, nil)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "direct image"
    assert document["file_id"] == "uploaded-photo-file-id"
    assert document["belongs_to_id"] == Integer.to_string(chat_id)
    assert document["media_type"] == "photo"
    assert document["image"] == Base.encode64(test_jpeg())
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_directs/321"
    refute Map.has_key?(document, "url")
    refute Map.has_key?(document, "download_url")

    assert_receive {:google_drive_upload_request, drive_env}

    assert URI.to_string(drive_env.url) ==
             "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

    assert drive_env.headers["authorization"] == ["Bearer test-drive-token"]
    drive_body = IO.iodata_to_binary(drive_env.body)
    assert binary_contains?(drive_body, ~s("name":"direct-photo.jpg"))
    assert binary_contains?(drive_body, "test-drive-folder")
    assert File.read(stored_file_path) == {:ok, test_jpeg()}
  end

  test "stores a private supergroup topic message URL for a directly uploaded photo", _context do
    chat_id = -1_001_234_567_890
    stored_file_path = storage_file_path("topic-direct-photo.jpg")

    File.rm(stored_file_path)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/topic-direct-photo.jpg"
    })

    message = %{
      chat: %{id: chat_id},
      message_id: 654,
      message_thread_id: 42,
      caption: "topic image",
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    Bot.handle({:message, message}, nil)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/c/1234567890/42/654"
  end

  test "stores a photo caption delivered as text by ExGram", _context do
    chat_id = 12_355
    stored_file_path = storage_file_path("caption-text-photo.jpg")

    File.rm(stored_file_path)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/caption-text-photo.jpg"
    })

    message = %{
      chat: %{id: chat_id, username: "save_it_directs"},
      message_id: 322,
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    Bot.handle({:text, "short-text", message}, nil)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "short-text"
    assert document["file_id"] == "uploaded-photo-file-id"
    assert document["belongs_to_id"] == Integer.to_string(chat_id)
    assert document["media_type"] == "photo"
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_directs/322"
  end

  test "stores an empty caption for a directly uploaded photo without user text", _context do
    chat_id = 12_350
    stored_file_path = storage_file_path("photo-without-caption.jpg")

    File.rm(stored_file_path)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    ExGramTestAdapter.backdoor_request(:get_file, %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/photo-without-caption.jpg"
    })

    message = %{
      chat: %{id: chat_id, username: "save_it_directs"},
      message_id: 323,
      photo: [%{file_id: "uploaded-photo-file-id"}]
    }

    Bot.handle({:message, message}, nil)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == ""
    assert document["file_id"] == "uploaded-photo-file-id"
    assert document["media_type"] == "photo"
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_directs/323"
  end

  test "stores a directly uploaded video using its thumbnail for Typesense and uploads the video to Google Drive",
       _context do
    chat_id = 12_347
    stored_file_path = storage_file_path("direct-video.mp4")

    File.rm(stored_file_path)
    configure_google_drive(chat_id)
    Application.put_env(:ex_gram, :adapter, __MODULE__.BodyAwareExGramAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.GoogleDriveAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    message = %{
      chat: %{id: chat_id, username: "save_it_directs"},
      message_id: 322,
      caption: "/similar",
      video: %{
        file_id: "uploaded-video-file-id",
        file_name: "direct-video.mp4",
        thumbnail: %{file_id: "uploaded-video-thumbnail-id"}
      }
    }

    Bot.handle({:message, message}, nil)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == ""
    assert document["file_id"] == "uploaded-video-file-id"
    assert document["belongs_to_id"] == Integer.to_string(chat_id)
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_jpeg())
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_directs/322"

    assert_receive {:google_drive_upload_request, drive_env}
    assert drive_env.headers["authorization"] == ["Bearer test-drive-token"]
    drive_body = IO.iodata_to_binary(drive_env.body)
    assert binary_contains?(drive_body, ~s("name":"direct-video.mp4"))
    assert binary_contains?(drive_body, "test-drive-folder")
    assert binary_contains?(drive_body, test_mp4())
    assert File.read(stored_file_path) == {:ok, test_mp4()}

    assert_receive {:exgram_request, :post, "/bottest-token/sendMessage",
                    %{chat_id: ^chat_id, text: "Similar photos found."}}

    assert_receive {:exgram_request, :post, "/bottest-token/sendVideo",
                    %{
                      chat_id: ^chat_id,
                      video: "similar-video-file",
                      caption: "similar video",
                      supports_streaming: true
                    }}
  end

  test "indexes a directly uploaded video thumbnail when Telegram refuses to download the large original video",
       _context do
    chat_id = 12_349

    configure_google_drive(chat_id)
    Application.put_env(:ex_gram, :adapter, __MODULE__.BodyAwareExGramAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.GoogleDriveAdapter.request/1
    )

    message = %{
      chat: %{id: chat_id},
      caption: "1-6",
      video: %{
        file_id: "oversized-video-file-id",
        file_name: "AI-voice-001.mp4",
        file_size: 33_527_186,
        thumbnail: %{file_id: "uploaded-video-thumbnail-id"}
      }
    }

    log =
      capture_log(fn ->
        Bot.handle({:message, message}, nil)
      end)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "1-6"
    assert document["file_id"] == "oversized-video-file-id"
    assert document["belongs_to_id"] == Integer.to_string(chat_id)
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_jpeg())

    assert log =~ "Skipping local backup for Telegram video"
    refute log =~ ~s({"ok":false)
    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage", %{chat_id: ^chat_id}}
    refute_receive {:google_drive_upload_request, _drive_env}
  end

  test "indexes a directly uploaded video thumbnail when original video download times out",
       _context do
    chat_id = 12_350
    stored_file_path = storage_file_path("timeout-video.mp4")

    File.rm(stored_file_path)
    configure_google_drive(chat_id)
    Application.put_env(:ex_gram, :adapter, __MODULE__.BodyAwareExGramAdapter)

    Application.put_env(:save_it, :telegram_req_options,
      adapter: &__MODULE__.TelegramDirectMediaAdapter.request/1
    )

    Application.put_env(:save_it, :google_drive_req_options,
      adapter: &__MODULE__.GoogleDriveAdapter.request/1
    )

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    message = %{
      chat: %{id: chat_id},
      caption: "timeout video",
      video: %{
        file_id: "timeout-video-file-id",
        file_name: "timeout-video.mp4",
        file_size: 3_343_466,
        thumbnail: %{file_id: "uploaded-video-thumbnail-id"}
      }
    }

    log =
      capture_log(fn ->
        Bot.handle({:message, message}, nil)
      end)

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "timeout video"
    assert document["file_id"] == "timeout-video-file-id"
    assert document["belongs_to_id"] == Integer.to_string(chat_id)
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_jpeg())

    assert log =~ "Skipping local backup for Telegram video"
    refute log =~ ":timeout"
    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage", %{chat_id: ^chat_id}}
    refute File.exists?(stored_file_path)
    refute_receive {:google_drive_upload_request, _drive_env}
  end

  test "returns details for a replied photo", _context do
    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 30})

    chat_id = 12_345
    original_url = "https://x.com/example/status/1?utm_source=telegram"

    message = %{
      chat: %{id: chat_id},
      reply_to_message: %{
        date: 1_717_200_000,
        photo: [
          %{file_id: "small-photo-file-id"},
          %{file_id: "telegram-photo-file-id"}
        ]
      }
    }

    assert {:ok, %{message_id: 30}} = Bot.handle({:command, :detail, message}, nil)

    assert_receive {:test_http_request, :get, search_path, ""}
    assert String.starts_with?(search_path, "/collections/photos/documents/search?")
    assert search_path =~ "file_id%3A%3Dtelegram-photo-file-id"
    assert search_path =~ "belongs_to_id%3A%3D12345"

    request_body = sent_message_body()

    assert request_body.chat_id == chat_id

    assert request_body.text ==
             Enum.join(
               [
                 "Message URL: https://t.me/save_it_test_chat/20",
                 "Original URL: #{original_url}",
                 "Saved at: 2024-06-01 00:00:00 UTC"
               ],
               "\n"
             )
  end

  test "omits missing values from photo details", _context do
    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 30})

    chat_id = 12_345

    message = %{
      chat: %{id: chat_id},
      reply_to_message: %{
        photo: [
          %{file_id: "small-photo-file-id"},
          %{file_id: "old-photo-file-id"}
        ]
      }
    }

    assert {:ok, %{message_id: 30}} = Bot.handle({:command, :detail, message}, nil)

    assert_receive {:test_http_request, :get, search_path, ""}
    assert search_path =~ "file_id%3A%3Dold-photo-file-id"

    request_body = sent_message_body()

    assert request_body.chat_id == chat_id
    assert request_body.text == "Saved at: 2024-06-01 00:00:00 UTC"
    refute request_body.text =~ "N/A"
    refute request_body.text =~ "Sent at:"
    refute request_body.text =~ "File ID:"
    refute request_body.text =~ "Typesense ID:"
    refute request_body.text =~ "Original URL:"
    refute request_body.text =~ "Download URL:"
    refute request_body.text =~ "Message URL:"
  end

  defp cleanup_cached_file(download_url, cached_file_name) do
    hashed_url = :crypto.hash(:sha256, download_url) |> Base.url_encode64(padding: false)
    url_cache_path = storage_url_path(hashed_url)
    file_path = storage_file_path(cached_file_name)

    File.rm(url_cache_path)
    File.rm(file_path)
  end

  defp assert_storage_file_with_uuidv7_extension(extension) do
    assert [file_name] =
             extension
             |> storage_file_names()
             |> Enum.filter(&uuidv7_file_name?(&1, extension))

    file_name
  end

  defp assert_storage_file_content_with_uuidv7_extension(extension, expected_content) do
    assert [file_name] =
             extension
             |> storage_file_names()
             |> Enum.filter(fn file_name ->
               uuidv7_file_name?(file_name, extension) and
                 File.read(storage_file_path(file_name)) == {:ok, expected_content}
             end)

    file_name
  end

  defp storage_file_names(extension) do
    case File.ls(FileHelper.files_dir()) do
      {:ok, file_names} -> Enum.filter(file_names, &(Path.extname(&1) == extension))
      {:error, _reason} -> []
    end
  end

  defp uuidv7_file_name?(file_name, extension) do
    Regex.match?(
      Regex.compile!(
        "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}#{Regex.escape(extension)}$"
      ),
      file_name
    )
  end

  defp storage_file_path(file_name), do: Path.join(FileHelper.files_dir(), file_name)
  defp storage_url_path(file_name), do: Path.join(FileHelper.urls_dir(), file_name)

  defp sent_message_body do
    ExGramTestAdapter.get_calls()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {:post, :send_message, body} ->
        body

      _ ->
        nil
    end)
  end

  defp cleanup_cached_folder(cache_key_url) do
    hashed_url = :crypto.hash(:sha256, cache_key_url) |> Base.url_encode64(padding: false)
    url_cache_path = storage_url_path(hashed_url)
    files_dir_path = storage_file_path(hashed_url)

    File.rm(url_cache_path)
    File.rm_rf(files_dir_path)
  end

  defp restore_env(app, env) do
    Application.get_all_env(app)
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
  end

  defp exgram_calls do
    ExGramTestAdapter.get_calls()
  end

  defp configure_google_drive(chat_id) do
    settings_dir = chat_settings_dir(chat_id)

    File.rm_rf(settings_dir)
    FileHelper.set_google_access_token(chat_id, "test-drive-token")
    FileHelper.set_google_drive_folder_id(chat_id, "test-drive-folder")

    on_exit(fn ->
      File.rm_rf(settings_dir)
    end)
  end

  defp chat_settings_dir(chat_id) do
    Path.join([FileHelper.data_dir(), "settings", to_string(chat_id)])
  end

  def test_jpeg do
    <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>
  end

  def test_og_jpeg do
    <<255, 216, 255, 224, 0, 16, 79, 71, 73, 70>>
  end

  def test_video_cover do
    <<255, 216, 255, 224, 0, 16, 67, 79, 86, 69, 82>>
  end

  def test_mp4 do
    <<0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50>>
  end

  defp binary_contains?(binary, pattern) do
    :binary.match(binary, pattern) != :nomatch
  end

  defp multipart_field(multipart, name) do
    multipart
    |> IO.iodata_to_binary()
    |> multipart_field_from_binary(name)
  end

  defp multipart_field_from_binary(multipart, name) do
    [_before_part, part] = :binary.split(multipart, ~s(name="#{name}"))
    [_headers, body] = :binary.split(part, "\r\n\r\n")
    [value, _rest] = :binary.split(body, "\r\n--")
    value
  end

  defp multipart_part(parts, name) when is_list(parts) do
    Enum.find_value(parts, fn
      {^name, value} -> value
      {_file_content, ^name, _content, _file_name} -> :file_content
      _part -> nil
    end)
  end

  defp multipart_file_content(parts, name) when is_list(parts) do
    Enum.find_value(parts, fn
      {:file_content, ^name, content, _file_name} -> content
      _part -> nil
    end)
  end

  defmodule BodyAwareExGramAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(self(), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:get, "/bottest-token/getFile", %{file_id: "oversized-video-file-id"}} ->
          {:error,
           %ExGram.Error{
             code: 400,
             message:
               ~s({"ok":false,"description":"Bad Request: file is too big","error_code":400})
           }}

        {:get, "/bottest-token/getFile", %{file_id: "uploaded-video-file-id"}} ->
          {:ok, %{file_id: "uploaded-video-file-id", file_path: "videos/direct-video.mp4"}}

        {:get, "/bottest-token/getFile", %{file_id: "timeout-video-file-id"}} ->
          {:ok, %{file_id: "timeout-video-file-id", file_path: "videos/timeout-video.mp4"}}

        {:get, "/bottest-token/getFile", %{file_id: "uploaded-video-thumbnail-id"}} ->
          {:ok,
           %{
             file_id: "uploaded-video-thumbnail-id",
             file_path: "video_thumbnails/direct-video.jpg"
           }}

        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 50, chat: %{id: chat_id}}}

        {:post, "/bottest-token/sendVideo", %{chat_id: chat_id, video: file_id}} ->
          {:ok, %{message_id: 51, chat: %{id: chat_id}, video: %{file_id: file_id}}}

        _ ->
          {:error, %ExGram.Error{code: 404}}
      end
    end
  end

  defmodule TopicSendPhotoAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(self(), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 76, chat: %{id: chat_id}}}

        {:post, "/bottest-token/editMessageText", _body} ->
          {:ok, %{message_id: 76}}

        {:post, "/bottest-token/deleteMessage", _body} ->
          {:ok, true}

        {:post, "/bottest-token/sendPhoto", {:multipart, parts}} ->
          {:ok,
           %{
             message_id: 77,
             message_thread_id:
               multipart_value(parts, "message_thread_id") |> String.to_integer(),
             chat: %{id: multipart_value(parts, "chat_id") |> String.to_integer()},
             photo: [%{file_id: "topic-photo-file-id"}]
           }}

        _ ->
          {:error, %ExGram.Error{code: 404}}
      end
    end

    defp multipart_value(parts, name) do
      Enum.find_value(parts, fn
        {^name, value} -> value
        _part -> nil
      end)
    end
  end

  defmodule UrlVideoThumbnailAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(self(), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 69, chat: %{id: chat_id}}}

        {:post, "/bottest-token/editMessageText", _body} ->
          {:ok, %{message_id: 69}}

        {:post, "/bottest-token/deleteMessage", _body} ->
          {:ok, true}

        {:post, "/bottest-token/sendVideo", {:multipart, parts}} ->
          chat_id = multipart_value(parts, "chat_id") |> String.to_integer()

          {:ok,
           %{
             message_id: 70,
             chat: %{id: chat_id},
             video: %{
               file_id: "sent-video-file-id",
               thumbnail: %{file_id: "sent-video-thumbnail-id"}
             }
           }}

        {:get, "/bottest-token/getFile", %{file_id: "sent-video-thumbnail-id"}} ->
          {:ok,
           %{
             file_id: "sent-video-thumbnail-id",
             file_path: "video_thumbnails/sent.jpg"
           }}

        _ ->
          {:error, %ExGram.Error{code: 404}}
      end
    end

    defp multipart_value(parts, name) do
      Enum.find_value(parts, fn
        {^name, value} -> value
        _part -> nil
      end)
    end
  end

  defmodule UrlVideoWithoutThumbnailAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(self(), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 68, chat: %{id: chat_id}}}

        {:post, "/bottest-token/editMessageText", _body} ->
          {:ok, %{message_id: 68}}

        {:post, "/bottest-token/deleteMessage", _body} ->
          {:ok, true}

        {:post, "/bottest-token/sendVideo", {:multipart, parts}} ->
          chat_id = multipart_value(parts, "chat_id") |> String.to_integer()

          {:ok,
           %{
             message_id: 71,
             chat: %{id: chat_id},
             video: %{file_id: "sent-video-file-id"}
           }}

        _ ->
          {:error, %ExGram.Error{code: 404}}
      end
    end

    defp multipart_value(parts, name) do
      Enum.find_value(parts, fn
        {^name, value} -> value
        _part -> nil
      end)
    end
  end

  defmodule HlsDownloadUrlResolver do
    def get_download_url(_url), do: {:ok, "https://stream.example/master.m3u8", :hls}
  end

  defmodule HlsDownloaderAdapter do
    def download(_m3u8_url) do
      {:ok,
       %SaveIt.DownloadedFile{
         file_name: SaveIt.FilenameGenerator.random("hls-output.mp4"),
         file_content: SaveIt.BotTest.test_mp4()
       }}
    end
  end

  defmodule VideoMetadataProbe do
    def probe_file_content(_file_content, file_name) when is_binary(file_name) do
      {:ok, %{width: 1080, height: 1920, duration: 12}}
    end

    def probe_file(_file_path), do: {:error, :unexpected_probe_file}
  end

  defmodule VideoCoverGenerator do
    def cover_file_content(_file_content, file_name, %{width: 180, height: 320})
        when is_binary(file_name) do
      {:ok, SaveIt.BotTest.test_video_cover()}
    end
  end

  defmodule FailingVideoCoverGenerator do
    def cover_file_content(_file_content, file_name, %{width: 180, height: 320})
        when is_binary(file_name) do
      {:error, :cover_unavailable}
    end
  end

  defmodule TelegramDirectMediaAdapter do
    def request(%Req.Request{method: :get, url: url} = request) do
      url = URI.to_string(url)
      send(self(), {:telegram_download_request, request})

      cond do
        String.contains?(url, "timeout-video.mp4") ->
          {request, Req.TransportError.exception(reason: :timeout)}

        String.contains?(url, "direct-video.mp4") ->
          {request, %Req.Response{status: 200, body: SaveIt.BotTest.test_mp4()}}

        true ->
          {request, %Req.Response{status: 200, body: SaveIt.BotTest.test_jpeg()}}
      end
    end
  end

  defmodule SimilarMediaFailureAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body, _opts) do
      send(self(), {:exgram_request, verb, path, body})

      case {verb, path, body} do
        {:get, "/bottest-token/getFile", %{file_id: "uploaded-photo-file-id"}} ->
          {:ok, %{file_id: "uploaded-photo-file-id", file_path: "photos/uploaded.jpg"}}

        {:post, "/bottest-token/sendMessage", %{chat_id: chat_id}} ->
          {:ok, %{message_id: 60, chat: %{id: chat_id}}}

        {:post, "/bottest-token/sendMediaGroup", %{chat_id: _chat_id}} ->
          {:error,
           %ExGram.Error{
             code: 400,
             message: "Bad Request: failed to get HTTP URL content"
           }}

        {:post, "/bottest-token/sendPhoto", %{photo: "sendable-similar-file"} = body} ->
          {:ok,
           %{
             message_id: 61,
             chat: %{id: body.chat_id},
             photo: [%{file_id: "sendable-similar-file"}]
           }}

        {:post, "/bottest-token/sendPhoto", %{photo: "broken-similar-file"}} ->
          {:error,
           %ExGram.Error{
             code: 400,
             message: "Bad Request: wrong file identifier"
           }}

        {:post, "/bottest-token/sendPhoto", %{photo: "broken-single-similar-file"}} ->
          {:error,
           %ExGram.Error{
             code: 400,
             message: "Bad Request: wrong file identifier"
           }}

        _ ->
          {:error, %ExGram.Error{code: 404}}
      end
    end
  end

  defmodule GoogleDriveAdapter do
    def request(%Req.Request{} = request) do
      send(self(), {:google_drive_upload_request, request})

      {request, %Req.Response{status: 200, body: %{"id" => "drive-file-id"}}}
    end
  end

  defmodule TelegramMediaGroupAdapter do
    def request(%Req.Request{} = request) do
      send(self(), {:telegram_media_group_request, request})

      {request,
       %Req.Response{
         status: 200,
         body: %{
           "ok" => true,
           "result" => [
             %{"message_id" => 101, "photo" => [%{"file_id" => "group-file-1"}]},
             %{"message_id" => 102, "photo" => [%{"file_id" => "group-file-2"}]},
             %{"message_id" => 103, "photo" => [%{"file_id" => "group-file-3"}]},
             %{"message_id" => 104, "photo" => [%{"file_id" => "group-file-4"}]}
           ]
         }
       }}
    end
  end

  defmodule TelegramDownloadAdapter do
    def request(%Req.Request{method: :get} = request) do
      send(self(), {:telegram_download_request, request})

      {request,
       %Req.Response{
         status: 200,
         body: <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>
       }}
    end
  end

  defmodule TestHttpServer do
    use GenServer

    defstruct [:listen_socket, :port, :test_pid, :acceptor_pid]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def port(server) do
      GenServer.call(server, :port)
    end

    def init(opts) do
      {:ok, listen_socket} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen_socket)
      test_pid = Keyword.fetch!(opts, :test_pid)

      state = %__MODULE__{
        listen_socket: listen_socket,
        port: port,
        test_pid: test_pid
      }

      {:ok, acceptor_pid} =
        Task.start_link(fn ->
          accept_loop(listen_socket, test_pid, port)
        end)

      {:ok, %{state | acceptor_pid: acceptor_pid}}
    end

    def handle_call(:port, _from, %{port: port} = state) do
      {:reply, port, state}
    end

    def terminate(_reason, %{listen_socket: listen_socket, acceptor_pid: acceptor_pid}) do
      if is_pid(acceptor_pid) do
        Process.exit(acceptor_pid, :normal)
      end

      :gen_tcp.close(listen_socket)
      :ok
    end

    defp accept_loop(listen_socket, test_pid, port) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, socket} ->
          handle_socket(socket, test_pid, port)
          accept_loop(listen_socket, test_pid, port)

        {:error, :closed} ->
          :ok
      end
    end

    defp handle_socket(socket, test_pid, port) do
      {method, path, body} = read_http_request(socket)
      send(test_pid, {:test_http_request, method, path, body})
      :gen_tcp.send(socket, response_for(path, port, body))
      :gen_tcp.close(socket)
    end

    defp response_for("/", port, body) do
      body
      |> Jason.decode!()
      |> cobalt_response(port)
    end

    defp response_for("/collections/photos/documents/search?" <> query, port, _body) do
      document =
        if query =~ "file_id%3A%3Dold-photo-file-id" do
          %{
            "id" => "old-typesense-photo-id",
            "caption" => "",
            "file_id" => "old-photo-file-id",
            "belongs_to_id" => "12345",
            "inserted_at" => 1_717_200_000
          }
        else
          %{
            "id" => "typesense-photo-id",
            "caption" => "",
            "file_id" => "telegram-photo-file-id",
            "url" => "https://x.com/example/status/1?utm_source=telegram",
            "download_url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg",
            "source_message_url" => "https://t.me/save_it_test_chat/20",
            "belongs_to_id" => "12345",
            "inserted_at" => 1_717_200_000
          }
        end

      json_response(%{
        "hits" => [
          %{
            "document" => document
          }
        ]
      })
    end

    defp response_for("/collections/photos/documents", _port, _body) do
      json_response(%{"id" => "typesense-photo-id"})
    end

    defp response_for("/multi_search", _port, body) do
      %{"searches" => [%{"filter_by" => filter_by}]} = Jason.decode!(body)

      json_response(%{
        "results" => [
          %{
            "hits" => similar_hits(filter_by)
          }
        ]
      })
    end

    defp response_for("/downloaded/video.mp4", _port, _body) do
      mp4 = SaveIt.BotTest.test_mp4()

      """
      HTTP/1.1 200 OK\r
      content-type: video/mp4; codecs="avc1.4d401f"\r
      content-length: #{byte_size(mp4)}\r
      connection: close\r
      \r
      #{mp4}
      """
    end

    defp response_for("/downloaded/" <> _file_name, _port, _body) do
      jpeg = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

      """
      HTTP/1.1 200 OK\r
      content-type: image/jpeg\r
      content-length: #{byte_size(jpeg)}\r
      connection: close\r
      \r
      #{jpeg}
      """
    end

    defp response_for("/preview-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="Preview Page OG Title">
          <meta property="og:description" content="Preview Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/preview.jpg">
        </head>
        <body>preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/x-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="X Page OG Title">
          <meta property="og:description" content="X Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/preview.jpg">
        </head>
        <body>x preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/x-title-only-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="X Title Only Page OG Title">
          <meta property="og:image" content="http://127.0.0.1:#{port}/preview.jpg">
        </head>
        <body>x title only preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/youtube-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="YouTube Page OG Title">
          <meta property="og:description" content="YouTube Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/video-preview.jpg">
        </head>
        <body>youtube preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/photo-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="Photo Page OG Title">
          <meta property="og:description" content="Photo Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/preview.jpg">
        </head>
        <body>photo preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for(path, port, _body)
         when path in ["/video-page", "/video-page-with-telegram-thumbnail"] do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="Video Page OG Title">
          <meta property="og:description" content="Video Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/video-preview.jpg">
        </head>
        <body>video preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/hls-video-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="HLS Video Page OG Title">
          <meta property="og:description" content="HLS Video Page OG Description">
          <meta property="og:image" content="http://127.0.0.1:#{port}/video-preview.jpg">
        </head>
        <body>video preview</body>
      </html>
      """

      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end

    defp response_for("/video-preview.jpg", _port, _body) do
      jpeg = SaveIt.BotTest.test_og_jpeg()

      """
      HTTP/1.1 200 OK\r
      content-type: image/jpeg\r
      content-length: #{byte_size(jpeg)}\r
      connection: close\r
      \r
      #{jpeg}
      """
    end

    defp response_for("/preview.jpg", _port, _body) do
      jpeg = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

      """
      HTTP/1.1 200 OK\r
      content-type: image/jpeg\r
      content-length: #{byte_size(jpeg)}\r
      connection: close\r
      \r
      #{jpeg}
      """
    end

    defp response_for(_path, _port, _body) do
      """
      HTTP/1.1 404 Not Found\r
      content-length: 0\r
      connection: close\r
      \r
      """
    end

    defp cobalt_response(%{"url" => "https://x.com/example/status/1"}, port) do
      json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg"})
    end

    defp cobalt_response(
           %{"url" => "https://x.com/JennerItGirls/status/2057529104535023815"},
           port
         ) do
      json_response(%{
        "status" => "picker",
        "picker" => [
          %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-1.jpg"},
          %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-2.jpg"},
          %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-3.jpg"},
          %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-4.jpg"}
        ]
      })
    end

    defp cobalt_response(%{"url" => "https://www.youtube.com/shorts/clip123"}, port) do
      json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/video.mp4"})
    end

    defp cobalt_response(%{"url" => "https://example.com/unavailable"}, _port) do
      error_response(%{"error" => "unsupported url"})
    end

    defp cobalt_response(%{"url" => "http://127.0.0.1:" <> _ = url}, port) do
      cond do
        String.contains?(url, "/photo-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg"})

        String.contains?(url, "/video-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/video.mp4"})

        true ->
          error_response(%{"error" => "unsupported url"})
      end
    end

    defp cobalt_response(unexpected, _port) do
      raise "Unexpected cobalt request body: #{inspect(unexpected)}"
    end

    defp similar_hits("belongs_to_id:12346") do
      [
        %{
          "document" => %{
            "file_id" => "single-similar-file",
            "caption" => "single similar"
          }
        }
      ]
    end

    defp similar_hits("belongs_to_id:12347") do
      [
        %{
          "document" => %{
            "file_id" => "similar-video-file",
            "caption" => "similar video",
            "media_type" => "video"
          }
        }
      ]
    end

    defp similar_hits("belongs_to_id:12348"), do: []
    defp similar_hits("belongs_to_id:12349"), do: []
    defp similar_hits("belongs_to_id:12350"), do: []

    defp similar_hits("belongs_to_id:12351") do
      [
        %{
          "document" => %{
            "file_id" => "broken-similar-file",
            "caption" => "broken similar"
          }
        },
        %{
          "document" => %{
            "file_id" => "sendable-similar-file",
            "caption" => "sendable similar"
          }
        }
      ]
    end

    defp similar_hits("belongs_to_id:12352") do
      [
        %{
          "document" => %{
            "file_id" => "broken-single-similar-file",
            "caption" => "broken single similar"
          }
        }
      ]
    end

    defp similar_hits("belongs_to_id:12353") do
      [
        %{
          "document" => %{
            "file_id" => "uploaded-photo-file-id",
            "caption" => ""
          }
        },
        %{
          "document" => %{
            "file_id" => "other-similar-file",
            "caption" => "other similar"
          }
        }
      ]
    end

    defp similar_hits(_filter_by) do
      [
        %{
          "document" => %{
            "file_id" => "similar-file-1",
            "caption" => "first similar"
          }
        },
        %{
          "document" => %{
            "file_id" => "similar-file-2",
            "caption" => "second similar"
          }
        }
      ]
    end

    defp json_response(body) do
      encoded_body = Jason.encode!(body)

      """
      HTTP/1.1 200 OK\r
      content-type: application/json\r
      content-length: #{byte_size(encoded_body)}\r
      connection: close\r
      \r
      #{encoded_body}
      """
    end

    defp error_response(body) do
      encoded_body = Jason.encode!(body)

      """
      HTTP/1.1 502 Bad Gateway\r
      content-type: application/json\r
      content-length: #{byte_size(encoded_body)}\r
      connection: close\r
      \r
      #{encoded_body}
      """
    end

    defp read_http_request(socket) do
      {:ok, initial_data} = :gen_tcp.recv(socket, 0, 5_000)
      {header_data, body_prefix} = split_headers(initial_data)
      [request_line | header_lines] = String.split(header_data, "\r\n", trim: true)
      [method, path, _http_version] = String.split(request_line, " ")
      content_length = parse_content_length(header_lines)

      body = read_body(socket, body_prefix, content_length)

      {String.downcase(method) |> String.to_atom(), path, body}
    end

    defp parse_content_length(header_lines) do
      Enum.find_value(header_lines, 0, &parse_content_length_header/1)
    end

    defp parse_content_length_header(line) do
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(name) == "content-length" do
            value |> String.trim() |> String.to_integer()
          end

        _ ->
          nil
      end
    end

    defp split_headers(data) do
      [headers, body] = :binary.split(data, "\r\n\r\n")
      {headers, body}
    end

    defp read_body(_socket, body_prefix, content_length)
         when byte_size(body_prefix) >= content_length do
      binary_part(body_prefix, 0, content_length)
    end

    defp read_body(socket, body_prefix, content_length) do
      remaining = content_length - byte_size(body_prefix)
      {:ok, body_suffix} = :gen_tcp.recv(socket, remaining, 5_000)
      body_prefix <> body_suffix
    end
  end
end
