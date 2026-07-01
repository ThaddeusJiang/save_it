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

  test "declares current bot commands without legacy command entries", _context do
    command_names = Enum.map(Bot.commands(), & &1[:command])

    assert "search" in command_names
    refute "similar" in command_names
    assert "google_drive_login" in command_names
    assert "google_drive_folder" in command_names
    refute "login" in command_names
    refute "code" in command_names
    refute "folder" in command_names
  end

  test "google drive login starts the device flow when there is no pending code", _context do
    configure_google_oauth()

    message = %{
      chat: %{id: 12_345, type: "private"},
      from: %{id: 1, is_bot: false}
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :google_drive_login, message}, nil)

    assert_receive {:google_oauth_request, request}
    assert request.method == :post
    assert request.url.path == "/device/code"
    assert FileHelper.get_google_device_code(12_345) == "device-code"

    sent_texts = sent_message_texts()

    assert Enum.any?(sent_texts, &String.contains?(&1, "https://www.google.com/device"))
    assert Enum.any?(sent_texts, &String.contains?(&1, "USER-CODE"))
    assert Enum.any?(sent_texts, &String.contains?(&1, "/google_drive_login"))
  end

  test "google drive login exchanges a pending device code", _context do
    configure_google_oauth()
    FileHelper.set_google_device_code(12_345, "device-code")

    message = %{
      chat: %{id: 12_345, type: "private"},
      from: %{id: 1, is_bot: false}
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :google_drive_login, message}, nil)

    assert_receive {:google_oauth_request, request}
    assert request.method == :post
    assert request.url.path == "/token"
    assert FileHelper.get_google_access_token(12_345) == "access-token"
    assert FileHelper.get_google_device_code(12_345) == ""
    assert sent_message_body().text =~ "Google Drive connected"
  end

  test "google drive login clears the pending device code when OAuth client is invalid",
       _context do
    configure_invalid_google_oauth_client()
    FileHelper.set_google_device_code(12_345, "device-code")

    message = %{
      chat: %{id: 12_345, type: "private"},
      from: %{id: 1, is_bot: false}
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :google_drive_login, message}, nil)

    assert_receive {:google_oauth_request, request}
    assert request.method == :post
    assert request.url.path == "/token"
    assert FileHelper.get_google_device_code(12_345) == ""

    sent_text = sent_message_body().text
    assert sent_text =~ "Google Drive login configuration is invalid"
    assert sent_text =~ "TVs and Limited Input devices"
    assert sent_text =~ "/google_drive_login"
  end

  test "google drive folder stores the configured folder id", _context do
    message = %{
      chat: %{id: 12_345, type: "private"},
      text: "  drive-folder-id  "
    }

    assert {:ok, %{message_id: 10}} = Bot.handle({:command, :google_drive_folder, message}, nil)

    assert FileHelper.get_google_drive_folder_id(12_345) == "drive-folder-id"
    assert sent_message_body().text == "Google Drive folder ID set successfully."
  end

  test "search command with text searches saved photos", _context do
    ExGramTestAdapter.backdoor_request(:send_media_group, [
      %{message_id: 31},
      %{message_id: 32}
    ])

    message = %{
      chat: %{id: 12_345},
      text: "summer"
    }

    assert :ok = Bot.handle({:command, :search, message}, nil)

    assert_receive {:test_http_request, :post, "/multi_search", body}

    %{"searches" => [%{"q" => "summer", "filter_by" => "belongs_to_id:=12345"} | _]} =
      Jason.decode!(body)

    assert Enum.any?(exgram_calls(), fn
             {:post, :send_media_group, %{chat_id: 12_345, media: media}} ->
               Enum.map(media, & &1.media) == ["similar-file-1", "similar-file-2"]

             _ ->
               false
           end)
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
    preview_url = base_url <> "/x-page"
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
      text: message_text,
      link_preview_options: %{url: preview_url}
    }

    assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}
    assert_receive {:test_http_request, :get, "/x-page", ""}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/preview.jpg"
    assert document["caption"] == "summer reference"
    assert document["title"] == "X Page OG Title"
    assert document["description"] == "X Page OG Description"
    assert document["keywords"] == ["x", "twitter", "clip"]
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

  test "stores URL metadata separately when user text only contains the URL", %{
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
    assert document["caption"] == ""
    assert document["title"] == "Photo Page OG Title"
    assert document["description"] == "Photo Page OG Description"
    assert document["keywords"] == ["photo", "reference", "save-it"]
  end

  test "stores x.com URL metadata separately when user text only contains the URL",
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
    assert document["caption"] == ""
    assert document["title"] == "X Page OG Title"
    assert document["description"] == "X Page OG Description"
    assert document["keywords"] == ["x", "twitter", "clip"]

    refute Enum.any?(exgram_calls(), fn
             {:post, :send_photo, {:multipart, parts}} ->
               {"caption", "X Page OG Description"} in parts

             _ ->
               false
           end)
  end

  test "stores missav.ai mirror OG metadata when direct preview fetch is blocked",
       %{base_url: base_url} do
    original_url = "https://missav.ai/ja/sdam-101-uncensored-leak"
    download_url = base_url <> "/downloaded/photo.jpg"

    Application.put_env(:save_it, :test_pid, self())

    Application.put_env(:save_it, :link_preview_req_options,
      adapter: &__MODULE__.MissavLinkPreviewAdapter.request/1
    )

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 103,
      text: original_url
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}
    assert_receive {:test_http_request, :get, "/downloaded/photo.jpg", ""}
    assert_receive {:link_preview_request, "https://missav.ai/ja/sdam-101-uncensored-leak"}
    assert_receive {:link_preview_request, "https://missav.ws/ja/sdam-101-uncensored-leak"}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == "https://fourhoi.com/sdam-101-uncensored-leak/cover-n.jpg"
    assert document["caption"] == ""
    assert document["title"] == "MissAV Mirror OG Title"
    assert document["description"] == "MissAV Mirror OG Description"
    assert document["keywords"] == ["missav", "metadata", "fallback"]
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
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
    assert multipart_part(parts, "caption") == ""

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    refute Map.has_key?(document, "source_message_id")
    assert document["download_url"] == download_url
    assert document["title"] == "X Page OG Title"
    assert document["description"] == "X Page OG Description"
    assert document["keywords"] == ["x", "twitter", "clip"]
    assert document["source_message_url"] == "https://t.me/c/1234567890/42/77"
  end

  test "stores x.com URL og title without using it as caption",
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
    assert document["caption"] == ""
    assert document["title"] == "X Title Only Page OG Title"
    refute Map.has_key?(document, "description")

    refute Enum.any?(exgram_calls(), fn
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

  test "stores youtube.com URL metadata separately when user text only contains the URL",
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
    assert multipart_part(parts, "caption") == ""

    assert_receive {:exgram_request, :get, "/bottest-token/getFile",
                    %{file_id: "sent-video-thumbnail-id"}}

    assert_receive {:telegram_download_request, _telegram_env}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["caption"] == ""
    assert document["title"] == "YouTube Page OG Title"
    assert document["description"] == "YouTube Page OG Description"
    assert document["keywords"] == ["youtube", "shorts", "clip"]

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
    assert document["caption"] == ""
    assert document["title"] == "Preview Page OG Title"
    assert document["description"] == "Preview Page OG Description"
    assert document["keywords"] == ["preview", "fallback", "save-it"]
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

  test "stores og image when the resolved URL resource is not image or video", %{
    base_url: base_url
  } do
    original_url = base_url <> "/article-page"
    message_text = "read later #{original_url}"

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 108,
      text: message_text,
      entities: [%{offset: 11, type: "url", length: String.length(original_url)}]
    }

    log =
      capture_log(fn ->
        assert {:ok, true} = Bot.handle({:text, message_text, message}, nil)
      end)

    assert log =~ "Saved webpage preview fallback after non-media URL download"

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}

    assert_receive {:test_http_request, :get, "/downloaded/article.html", ""}
    assert_receive {:test_http_request, :get, "/article-page", ""}
    assert_receive {:test_http_request, :get, "/preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    refute Map.has_key?(document, "download_url")
    assert document["thumbnail_url"] == base_url <> "/preview.jpg"
    assert document["caption"] == "read later"
    assert document["title"] == "Article Page OG Title"
    assert document["description"] == "Article Page OG Description"
    assert document["keywords"] == ["article", "preview", "save-it"]
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["image"] == Base.encode64(test_jpeg())

    refute Enum.any?(exgram_calls(), fn
             {:post, :send_document, _body} -> true
             _ -> false
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
    assert multipart_file_content(parts, "thumbnail") == test_video_thumbnail()
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

  test "sends a thumbnail and indexes Typesense when downloaded URL video is too large for Telegram",
       %{base_url: base_url} do
    original_url = base_url <> "/large-video-page"
    download_url = base_url <> "/downloaded/large-video.mp4"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoThumbnailAdapter)
    Application.put_env(:save_it, :video_upload_preparer, __MODULE__.VideoUploadPreparer)
    Application.put_env(:save_it, :video_metadata_probe, __MODULE__.VideoMetadataProbe)
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.VideoCoverGenerator)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 106,
      text: "large clip #{original_url}",
      link_preview_options: %{url: original_url}
    }

    assert {:ok, true} = Bot.handle({:text, message.text, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => original_url}
    assert_receive {:test_http_request, :get, "/downloaded/large-video.mp4", ""}

    refute_receive {:exgram_request, :post, "/bottest-token/sendVideo", _body}

    assert_receive {:exgram_request, :post, "/bottest-token/sendPhoto", {:multipart, parts}}
    assert multipart_part(parts, "chat_id") == "12345"

    assert multipart_part(parts, "caption") ==
             "large clip\n\nVideo downloaded; Telegram upload was too large."

    assert multipart_part(parts, "photo") == :file_content
    assert multipart_file_content(parts, "photo") == test_video_cover()

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["caption"] == "large clip"
    assert document["title"] == "Video Page OG Title"
    assert document["description"] == "Video Page OG Description"
    assert document["keywords"] == ["video", "preview", "clip"]
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["media_type"] == "video"
    assert document["image"] == Base.encode64(test_video_cover())
    refute Map.has_key?(document, "source_message_id")
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/72"

    assert_receive {:test_http_request, :get, "/large-video-page", ""}
    refute_receive {:test_http_request, :get, "/video-preview.jpg", ""}

    assert_storage_file_with_uuidv7_extension(".mp4")
    assert_storage_file_content_with_uuidv7_extension(".jpg", test_video_cover())
  end

  test "logs the URL processing flow at debug level", %{base_url: base_url} do
    preview_url = base_url <> "/video-page"
    original_url = preview_url <> "?token=secret"

    Application.put_env(:ex_gram, :adapter, __MODULE__.UrlVideoWithoutThumbnailAdapter)
    Application.put_env(:save_it, :video_upload_preparer, __MODULE__.VideoUploadPreparer)
    Application.put_env(:save_it, :video_cover_generator, __MODULE__.VideoCoverGenerator)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 107,
      text: original_url,
      link_preview_options: %{url: preview_url}
    }

    previous_level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log([level: :debug], fn ->
          assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)
        end)
      after
        Logger.configure(level: previous_level)
      end

    assert log =~ "URL processing started"
    assert log =~ ~s(source_url="#{base_url}/video-page")
    assert log =~ "URL download resolved result=single"
    assert log =~ ~s(download_url="#{base_url}/downloaded/video.mp4")
    assert log =~ "Link preview metadata fetched"
    assert log =~ ~s(og_title="Video Page OG Title")
    assert log =~ ~s(og_description="Video Page OG Description")
    assert log =~ ~s(keywords="video, preview, clip")
    assert log =~ "URL file downloaded"
    assert log =~ "Telegram media send started media_type=video"
    assert log =~ "Typesense photo indexing started media_type=video"
    refute log =~ "token=secret"
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
    assert document["caption"] == ""
    assert document["title"] == "Video Page OG Title"
    assert document["description"] == "Video Page OG Description"
    assert document["keywords"] == ["video", "preview", "clip"]
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
    assert multipart_part(parts, "caption") == ""
    assert multipart_part(parts, "supports_streaming") == "true"

    assert_receive {:test_http_request, :get, "/video-page", ""}
    assert_receive {:test_http_request, :get, "/video-preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["thumbnail_url"] == base_url <> "/video-preview.jpg"
    assert document["caption"] == ""
    assert document["title"] == "Video Page OG Title"
    assert document["description"] == "Video Page OG Description"
    assert document["keywords"] == ["video", "preview", "clip"]
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
    assert multipart_part(parts, "caption") == ""
    assert multipart_part(parts, "supports_streaming") == "true"

    assert_receive {:test_http_request, :get, "/hls-video-page", ""}
    assert_receive {:test_http_request, :get, "/video-preview.jpg", ""}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == "https://stream.example/master.m3u8"
    assert document["thumbnail_url"] == base_url <> "/video-preview.jpg"
    assert document["caption"] == ""
    assert document["title"] == "HLS Video Page OG Title"
    assert document["description"] == "HLS Video Page OG Description"
    assert document["keywords"] == ["hls", "video", "stream"]
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

  test "handles /search command attached to a photo as similar image search", _context do
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

    assert :ok = Bot.handle({:command, :search, message}, nil)

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
      caption: "/search",
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
      caption: "/search",
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
      caption: "/search",
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
      caption: "/search",
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
      caption: "/search",
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

    assert_google_drive_resumable_upload("direct-photo.jpg", test_jpeg())
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
      caption: "/search",
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

    assert_google_drive_resumable_upload("direct-video.mp4", test_mp4())
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
                 "Caption: saved by user",
                 "Title: X Page OG Title",
                 "Description: X Page OG Description",
                 "Keywords: x, twitter, clip",
                 "Saved at: 2024-06-01 00:00:00 UTC"
               ],
               "\n"
             )
  end

  test "returns details for a replied video", _context do
    ExGramTestAdapter.backdoor_request(:send_message, %{message_id: 30})

    chat_id = 12_345

    message = %{
      chat: %{id: chat_id},
      reply_to_message: %{
        date: 1_717_200_000,
        video: %{file_id: "sent-video-file-id"}
      }
    }

    assert {:ok, %{message_id: 30}} = Bot.handle({:command, :detail, message}, nil)

    assert_receive {:test_http_request, :get, search_path, ""}
    assert String.starts_with?(search_path, "/collections/photos/documents/search?")
    assert search_path =~ "file_id%3A%3Dsent-video-file-id"
    assert search_path =~ "belongs_to_id%3A%3D12345"

    request_body = sent_message_body()

    assert request_body.chat_id == chat_id

    assert request_body.text ==
             Enum.join(
               [
                 "Message URL: https://t.me/save_it_test_chat/70",
                 "Original URL: https://www.youtube.com/shorts/clip123",
                 "Caption: video saved by user",
                 "Title: Video Page OG Title",
                 "Description: Video Page OG Description",
                 "Keywords: video, preview, clip",
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

  defp sent_message_texts do
    ExGramTestAdapter.get_calls()
    |> Enum.filter(fn
      {:post, :send_message, _body} -> true
      _ -> false
    end)
    |> Enum.map(fn {:post, :send_message, body} -> body.text end)
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

  defp configure_google_oauth do
    Application.put_env(:save_it, :google_oauth_client_id, "client-id")
    Application.put_env(:save_it, :google_oauth_client_secret, "client-secret")

    Application.put_env(:save_it, :google_oauth_req_options,
      adapter: &__MODULE__.GoogleOAuthAdapter.request/1
    )
  end

  defp configure_invalid_google_oauth_client do
    Application.put_env(:save_it, :google_oauth_client_id, "client-id")
    Application.put_env(:save_it, :google_oauth_client_secret, "client-secret")

    Application.put_env(:save_it, :google_oauth_req_options,
      adapter: &__MODULE__.InvalidGoogleOAuthClientAdapter.request/1
    )
  end

  defp chat_settings_dir(chat_id) do
    Path.join([FileHelper.data_dir(), "settings", to_string(chat_id)])
  end

  defp assert_google_drive_resumable_upload(file_name, file_content) do
    assert_receive {:google_drive_upload_request, create_session_request}

    assert URI.to_string(create_session_request.url) ==
             "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"

    assert create_session_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert create_session_request.headers["x-upload-content-type"] == ["application/octet-stream"]

    assert create_session_request.headers["x-upload-content-length"] == [
             Integer.to_string(byte_size(file_content))
           ]

    assert Jason.decode!(IO.iodata_to_binary(create_session_request.body)) == %{
             "name" => file_name,
             "parents" => ["test-drive-folder"]
           }

    assert_receive {:google_drive_upload_request, upload_request}
    assert URI.to_string(upload_request.url) == "https://uploads.example/session"
    assert upload_request.headers["authorization"] == ["Bearer test-drive-token"]
    assert upload_request.headers["content-type"] == ["application/octet-stream"]

    assert upload_request.headers["content-length"] == [
             Integer.to_string(byte_size(file_content))
           ]

    assert upload_request.headers["content-range"] == [
             "bytes 0-#{byte_size(file_content) - 1}/#{byte_size(file_content)}"
           ]

    assert IO.iodata_to_binary(upload_request.body) == file_content
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

  def test_video_thumbnail do
    <<255, 216, 255, 224, 0, 16, 84, 72, 85, 77, 66>>
  end

  def test_mp4 do
    <<0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50>>
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

  defmodule MissavLinkPreviewAdapter do
    def request(%Req.Request{url: url} = request) do
      send(
        Application.fetch_env!(:save_it, :test_pid),
        {:link_preview_request, URI.to_string(url)}
      )

      response =
        case {url.host, url.path} do
          {"missav.ai", "/ja/sdam-101-uncensored-leak"} ->
            %Req.Response{status: 403, body: "Just a moment..."}

          {"missav.ws", "/ja/sdam-101-uncensored-leak"} ->
            %Req.Response{
              status: 200,
              body: """
              <html>
                <head>
                  <meta property="og:title" content="MissAV Mirror OG Title" />
                  <meta property="og:description" content="MissAV Mirror OG Description" />
                  <meta name="keywords" content="missav, metadata, fallback" />
                  <meta property="og:image" content="https://fourhoi.com/sdam-101-uncensored-leak/cover-n.jpg" />
                </head>
              </html>
              """
            }

          unexpected ->
            raise "Unexpected MissAV preview request: #{inspect(unexpected)}"
        end

      {request, response}
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

        {:post, "/bottest-token/sendPhoto", {:multipart, parts}} ->
          chat_id = multipart_value(parts, "chat_id") |> String.to_integer()

          {:ok,
           %{
             message_id: 72,
             chat: %{id: chat_id},
             photo: [%{file_id: "telegram-photo-file-id"}]
           }}

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

  defmodule VideoUploadPreparer do
    def prepare_file_content(file_content, file_name)
        when is_binary(file_content) and is_binary(file_name) do
      {:ok, file_content, %{width: 1080, height: 1920, duration: 12}}
    end
  end

  defmodule VideoCoverGenerator do
    def cover_file_content(_file_content, file_name, %{width: 1080, height: 1920, jpeg_quality: 2})
        when is_binary(file_name) do
      {:ok, SaveIt.BotTest.test_video_cover()}
    end

    def cover_file_content(_file_content, file_name, %{width: 180, height: 320, jpeg_quality: 5})
        when is_binary(file_name) do
      {:ok, SaveIt.BotTest.test_video_thumbnail()}
    end
  end

  defmodule FailingVideoCoverGenerator do
    def cover_file_content(_file_content, file_name, _dimensions)
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

      response =
        case {request.method, request.url.path, request.url.query} do
          {:post, "/upload/drive/v3/files", "uploadType=resumable"} ->
            Req.Response.new(
              status: 200,
              headers: [{"location", "https://uploads.example/session"}],
              body: ""
            )

          {:put, "/session", nil} ->
            %Req.Response{status: 201, body: %{"id" => "drive-file-id"}}
        end

      {request, response}
    end
  end

  defmodule GoogleOAuthAdapter do
    def request(%Req.Request{} = request) do
      send(self(), {:google_oauth_request, request})

      response_body =
        case request.url.path do
          "/device/code" ->
            %{
              "device_code" => "device-code",
              "user_code" => "USER-CODE",
              "verification_url" => "https://www.google.com/device"
            }

          "/token" ->
            %{"access_token" => "access-token"}
        end

      {request, %Req.Response{status: 200, body: response_body}}
    end
  end

  defmodule InvalidGoogleOAuthClientAdapter do
    def request(%Req.Request{} = request) do
      send(self(), {:google_oauth_request, request})

      {request,
       %Req.Response{
         status: 401,
         body: %{
           "error" => "invalid_client",
           "error_description" => "The OAuth client was not found."
         }
       }}
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
        cond do
          query =~ "file_id%3A%3Dold-photo-file-id" ->
            %{
              "id" => "old-typesense-photo-id",
              "caption" => "",
              "file_id" => "old-photo-file-id",
              "belongs_to_id" => "12345",
              "inserted_at" => 1_717_200_000
            }

          query =~ "file_id%3A%3Dsent-video-file-id" ->
            %{
              "id" => "typesense-video-id",
              "file_id" => "sent-video-file-id",
              "caption" => "video saved by user",
              "title" => "Video Page OG Title",
              "description" => "Video Page OG Description",
              "keywords" => ["video", "preview", "clip"],
              "url" => "https://www.youtube.com/shorts/clip123",
              "download_url" => "http://127.0.0.1:#{port}/downloaded/video.mp4",
              "source_message_url" => "https://t.me/save_it_test_chat/70",
              "media_type" => "video",
              "belongs_to_id" => "12345",
              "inserted_at" => 1_717_200_000
            }

          true ->
            %{
              "id" => "typesense-photo-id",
              "file_id" => "telegram-photo-file-id",
              "caption" => "saved by user",
              "title" => "X Page OG Title",
              "description" => "X Page OG Description",
              "keywords" => ["x", "twitter", "clip"],
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
      %{"searches" => [%{"filter_by" => filter_by} | _]} = Jason.decode!(body)

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

    defp response_for("/downloaded/large-video.mp4", _port, _body) do
      mp4 = :binary.copy(<<0>>, 50 * 1024 * 1024 + 1)

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
          <meta name="keywords" content="preview, fallback, save-it">
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
          <meta name="keywords" content="x, twitter, clip">
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
          <meta name="keywords" content="youtube, shorts, clip">
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
          <meta name="keywords" content="photo, reference, save-it">
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

    defp response_for("/article-page", port, _body) do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="Article Page OG Title">
          <meta property="og:description" content="Article Page OG Description">
          <meta name="keywords" content="article, preview, save-it">
          <meta property="og:image" content="http://127.0.0.1:#{port}/preview.jpg">
        </head>
        <body>article preview</body>
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
         when path in ["/video-page", "/video-page-with-telegram-thumbnail", "/large-video-page"] do
      html = """
      <!doctype html>
      <html>
        <head>
          <meta property="og:title" content="Video Page OG Title">
          <meta property="og:description" content="Video Page OG Description">
          <meta name="keywords" content="video, preview, clip">
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
          <meta name="keywords" content="hls, video, stream">
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

    defp cobalt_response(%{"url" => "https://missav.ai/ja/sdam-101-uncensored-leak"}, port) do
      json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg"})
    end

    defp cobalt_response(%{"url" => "https://example.com/unavailable"}, _port) do
      error_response(%{"error" => "unsupported url"})
    end

    defp cobalt_response(%{"url" => "http://127.0.0.1:" <> _ = url}, port) do
      cond do
        String.contains?(url, "/photo-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg"})

        String.contains?(url, "/article-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/article.html"})

        String.contains?(url, "/video-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/video.mp4"})

        String.contains?(url, "/large-video-page") ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/large-video.mp4"})

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
