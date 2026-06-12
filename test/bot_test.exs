defmodule SaveIt.BotTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ExGram.Adapter.Test, as: ExGramTestAdapter
  alias SaveIt.Bot
  alias SaveIt.FileHelper

  setup do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    previous_ex_gram = Application.get_all_env(:ex_gram)
    previous_save_it = Application.get_all_env(:save_it)
    previous_small_sdk_telegram = Application.get_env(:tesla, SmallSdk.Telegram)

    Application.put_env(:ex_gram, :adapter, ExGram.Adapter.Test)
    Application.put_env(:ex_gram, :token, "test-token")
    Application.put_env(:save_it, :cobalt_api_url, base_url)
    Application.put_env(:save_it, :telegram_bot_token, "test-token")
    Application.put_env(:save_it, :typesense_url, base_url)
    Application.put_env(:save_it, :typesense_api_key, "test-typesense-key")
    Application.put_env(:save_it, :timezone, System.get_env("TZ") || "Asia/Tokyo")

    if Process.whereis(ExGram.Adapter.Test) do
      ExGramTestAdapter.clean()
    else
      start_supervised!(%{
        id: ExGram.Adapter.Test,
        start: {ExGram.Adapter.Test, :start_link, [[]]}
      })
    end

    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 10})
    ExGramTestAdapter.backdoor_request("/editMessageText", %{message_id: 10})
    ExGramTestAdapter.backdoor_request("/deleteMessage", true)

    ExGramTestAdapter.backdoor_request("/sendPhoto", %{
      message_id: 20,
      photo: [%{file_id: "telegram-photo-file-id"}]
    })

    on_exit(fn ->
      if Process.whereis(ExGram.Adapter.Test) do
        ExGramTestAdapter.clean()
      end

      restore_env(:tesla, SmallSdk.Telegram, previous_small_sdk_telegram)
      restore_env(:ex_gram, previous_ex_gram)
      restore_env(:save_it, previous_save_it)
    end)

    %{base_url: base_url}
  end

  test "stores the original user-sent url when indexing a downloaded photo", %{base_url: base_url} do
    with_env("TZ", nil)
    Application.put_env(:save_it, :timezone, "Asia/Tokyo")

    original_url = "https://x.com/example/status/1?utm_source=telegram"
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
      message_id: 99
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    refute Map.has_key?(document, "download_url")
    assert document["caption"] == "created at 2024-06-01"
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
    assert document["source_message_id"] == 20
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/20"

    assert Enum.any?(exgram_calls(), fn
             {:post, "/bottest-token/sendPhoto", {:multipart, parts}} ->
               {"caption", "created at 2024-06-01"} in parts and
                 not Enum.any?(parts, &match?({"show_caption_above_media", _}, &1))

             _ ->
               false
           end)
  end

  test "uses TZ when captioning a downloaded photo", %{base_url: base_url} do
    with_env("TZ", "UTC")
    Application.put_env(:save_it, :timezone, System.get_env("TZ") || "Asia/Tokyo")

    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-time-zone-test.jpg"
    cached_file_content = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    FileHelper.write_file(cached_file_name, cached_file_content, download_url)

    on_exit(fn ->
      cleanup_cached_file(download_url, cached_file_name)
    end)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_170_000,
      message_id: 98
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", _cobalt_body}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "created at 2024-05-31"
  end

  test "uses configured timezone when TZ is not set", %{base_url: base_url} do
    with_env("TZ", nil)
    Application.put_env(:save_it, :timezone, "UTC")

    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-config-default-time-zone-test.jpg"
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

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", _cobalt_body}
    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["caption"] == "created at 2024-05-31"
  end

  test "stores the Telegram thumbnail when a user-sent url cannot be resolved", _context do
    original_url = "https://example.com/unavailable"

    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDownloadAdapter)

    ExGramTestAdapter.backdoor_request("/getFile", %{
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
    assert String.ends_with?(telegram_env.url, "/file/bottest-token/photos/link-thumbnail.jpg")

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    refute Map.has_key?(document, "download_url")
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
    assert document["source_message_id"] == 20
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
    assert document["caption"] == "created at 2024-06-01"
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["source_message_id"] == 20
    assert document["source_message_url"] == "https://t.me/save_it_test_chat/20"

    refute Enum.any?(exgram_calls(), fn
             {:post, _path, %{text: text}} when is_binary(text) ->
               String.contains?(text, "Failed")

             _ ->
               false
           end)
  end

  test "stores the original user-sent url for every photo in a multi-image download", _context do
    original_url = "https://x.com/JennerItGirls/status/2057529104535023815?s=20"
    purge_url = "https://x.com/JennerItGirls/status/2057529104535023815"

    cleanup_cached_folder(purge_url)

    on_exit(fn ->
      cleanup_cached_folder(purge_url)
    end)

    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramMediaGroupAdapter)

    message = %{
      chat: %{id: 12_345, username: "save_it_test_chat"},
      date: 1_717_200_000,
      message_id: 100
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}

    assert Jason.decode!(cobalt_body) == %{
             "url" => "https://x.com/JennerItGirls/status/2057529104535023815"
           }

    assert_receive {:telegram_media_group_request, conn}

    media =
      conn.body
      |> multipart_field("media")
      |> Jason.decode!()

    assert Enum.map(media, & &1["caption"]) == List.duplicate("created at 2024-06-01", 4)
    refute Enum.any?(media, &Map.has_key?(&1, "show_caption_above_media"))

    documents =
      Enum.map(1..4, fn _ ->
        assert_receive {:test_http_request, :post, "/collections/photos/documents",
                        typesense_body}

        Jason.decode!(typesense_body)
      end)

    assert Enum.map(documents, & &1["url"]) == List.duplicate(original_url, 4)
    assert Enum.map(documents, & &1["caption"]) == List.duplicate("created at 2024-06-01", 4)
    refute Enum.any?(documents, &Map.has_key?(&1, "download_url"))

    assert Enum.map(documents, & &1["file_id"]) == [
             "group-file-1",
             "group-file-2",
             "group-file-3",
             "group-file-4"
           ]

    assert Enum.map(documents, & &1["source_message_id"]) == [101, 102, 103, 104]

    assert Enum.map(documents, & &1["source_message_url"]) == [
             "https://t.me/save_it_test_chat/101",
             "https://t.me/save_it_test_chat/102",
             "https://t.me/save_it_test_chat/103",
             "https://t.me/save_it_test_chat/104"
           ]
  end

  test "announces similar photos and sends multiple results as one media group", _context do
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDownloadAdapter)

    ExGramTestAdapter.backdoor_request("/getFile", %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 30})

    ExGramTestAdapter.backdoor_request("/sendMediaGroup", [
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

    assert {:post, "/bottest-token/sendMessage",
            %{chat_id: 12_345, text: "Similar photos found."}} in calls

    media_group_calls =
      Enum.filter(calls, fn
        {:post, "/bottest-token/sendMediaGroup", _body} -> true
        _ -> false
      end)

    assert [
             {:post, "/bottest-token/sendMediaGroup", %{chat_id: 12_345, media: media}}
           ] = media_group_calls

    assert Enum.map(media, & &1.media) == ["similar-file-1", "similar-file-2"]
    assert Enum.map(media, & &1.caption) == ["first similar", "second similar"]
    refute Enum.any?(media, &Map.has_key?(&1, :show_caption_above_media))
  end

  test "announces similar photos and sends one result as one photo", _context do
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDownloadAdapter)

    ExGramTestAdapter.backdoor_request("/getFile", %{
      file_id: "uploaded-photo-file-id",
      file_path: "photos/uploaded.jpg"
    })

    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 40})

    ExGramTestAdapter.backdoor_request("/sendPhoto", %{
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

    assert {:post, "/bottest-token/sendMessage",
            %{chat_id: 12_346, text: "Similar photos found."}} in calls

    assert Enum.any?(calls, fn
             {:post, "/bottest-token/sendPhoto",
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
             {:post, "/bottest-token/sendMediaGroup", _body} -> true
             _ -> false
           end)
  end

  test "silently skips similar photos that Telegram cannot send after media group failure",
       _context do
    Application.put_env(:ex_gram, :adapter, __MODULE__.SimilarMediaFailureAdapter)
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDownloadAdapter)

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
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDownloadAdapter)

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
    stored_file_path = Path.join(["./data/storage/files", "direct-photo.jpg"])

    File.rm(stored_file_path)
    configure_google_drive(chat_id)
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDirectMediaAdapter)
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveAdapter)

    on_exit(fn ->
      File.rm(stored_file_path)
    end)

    ExGramTestAdapter.backdoor_request("/getFile", %{
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
    assert document["source_message_id"] == 321
    assert document["source_message_url"] == "https://t.me/save_it_directs/321"
    refute Map.has_key?(document, "url")
    refute Map.has_key?(document, "download_url")

    assert_receive {:google_drive_upload_request, drive_env}
    assert drive_env.url == "https://www.googleapis.com/upload/drive/v3/files"
    assert {"Authorization", "Bearer test-drive-token"} in drive_env.headers
    assert binary_contains?(drive_env.body, ~s("name":"direct-photo.jpg"))
    assert binary_contains?(drive_env.body, "test-drive-folder")
    assert File.read(stored_file_path) == {:ok, test_jpeg()}
  end

  test "stores a directly uploaded video using its thumbnail for Typesense and uploads the video to Google Drive",
       _context do
    chat_id = 12_347
    stored_file_path = Path.join(["./data/storage/files", "direct-video.mp4"])

    File.rm(stored_file_path)
    configure_google_drive(chat_id)
    Application.put_env(:ex_gram, :adapter, __MODULE__.BodyAwareExGramAdapter)
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDirectMediaAdapter)
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveAdapter)

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
    assert document["source_message_id"] == 322
    assert document["source_message_url"] == "https://t.me/save_it_directs/322"

    assert_receive {:google_drive_upload_request, drive_env}
    assert {"Authorization", "Bearer test-drive-token"} in drive_env.headers
    assert binary_contains?(drive_env.body, ~s("name":"direct-video.mp4"))
    assert binary_contains?(drive_env.body, "test-drive-folder")
    assert binary_contains?(drive_env.body, test_mp4())
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
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDirectMediaAdapter)
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveAdapter)

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
    assert log =~ "file is too big"
    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage", %{chat_id: ^chat_id}}
    refute_receive {:google_drive_upload_request, _drive_env}
  end

  test "indexes a directly uploaded video thumbnail when original video download times out",
       _context do
    chat_id = 12_350
    stored_file_path = Path.join(["./data/storage/files", "timeout-video.mp4"])

    File.rm(stored_file_path)
    configure_google_drive(chat_id)
    Application.put_env(:ex_gram, :adapter, __MODULE__.BodyAwareExGramAdapter)
    Application.put_env(:tesla, SmallSdk.Telegram, adapter: __MODULE__.TelegramDirectMediaAdapter)
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveAdapter)

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
    assert log =~ ":timeout"
    refute_receive {:exgram_request, :post, "/bottest-token/sendMessage", %{chat_id: ^chat_id}}
    refute File.exists?(stored_file_path)
    refute_receive {:google_drive_upload_request, _drive_env}
  end

  test "returns details for a replied photo", _context do
    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 30})

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
    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 30})

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
    url_cache_path = Path.join(["./data/storage/urls", hashed_url])
    file_path = Path.join(["./data/storage/files", cached_file_name])

    File.rm(url_cache_path)
    File.rm(file_path)
  end

  defp sent_message_body do
    %{calls: calls} = :sys.get_state(ExGram.Adapter.Test)

    calls
    |> Enum.reverse()
    |> Enum.find_value(fn
      {:post, path, body} ->
        if String.ends_with?(path, "/sendMessage"), do: body

      _ ->
        nil
    end)
  end

  defp cleanup_cached_folder(cache_key_url) do
    hashed_url = :crypto.hash(:sha256, cache_key_url) |> Base.url_encode64(padding: false)
    url_cache_path = Path.join(["./data/storage/urls", hashed_url])
    files_dir_path = Path.join(["./data/storage/files", hashed_url])

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

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp exgram_calls do
    ExGram.Adapter.Test
    |> :sys.get_state()
    |> Map.fetch!(:calls)
  end

  defp configure_google_drive(chat_id) do
    File.rm_rf("./data/settings/#{chat_id}")
    FileHelper.set_google_access_token(chat_id, "test-drive-token")
    FileHelper.set_google_drive_folder_id(chat_id, "test-drive-folder")

    on_exit(fn ->
      File.rm_rf("./data/settings/#{chat_id}")
    end)
  end

  def test_jpeg do
    <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>
  end

  def test_mp4 do
    <<0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50>>
  end

  defp binary_contains?(binary, pattern) do
    :binary.match(binary, pattern) != :nomatch
  end

  defp with_env(key, value) do
    previous_value = System.get_env(key)

    if is_nil(value) do
      System.delete_env(key)
    else
      System.put_env(key, value)
    end

    on_exit(fn ->
      if is_nil(previous_value) do
        System.delete_env(key)
      else
        System.put_env(key, previous_value)
      end
    end)
  end

  defp multipart_field(multipart, name) do
    multipart.parts
    |> Enum.find(fn part -> part.dispositions[:name] == name end)
    |> Map.fetch!(:body)
  end

  defmodule BodyAwareExGramAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body) do
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

  defmodule TelegramDirectMediaAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{method: :get, url: url} = env, _opts) do
      send(self(), {:telegram_download_request, env})

      cond do
        String.contains?(url, "timeout-video.mp4") ->
          {:error, :timeout}

        String.contains?(url, "direct-video.mp4") ->
          {:ok, %{env | status: 200, body: SaveIt.BotTest.test_mp4()}}

        true ->
          {:ok, %{env | status: 200, body: SaveIt.BotTest.test_jpeg()}}
      end
    end
  end

  defmodule SimilarMediaFailureAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(verb, path, body) do
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
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(self(), {:google_drive_upload_request, env})
      {:ok, %{env | status: 200, body: %{"id" => "drive-file-id"}}}
    end
  end

  defmodule TelegramMediaGroupAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(self(), {:telegram_media_group_request, env})

      {:ok,
       %Tesla.Env{
         env
         | status: 200,
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
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{method: :get} = env, _opts) do
      send(self(), {:telegram_download_request, env})

      {:ok,
       %Tesla.Env{
         env
         | status: 200,
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
      case Jason.decode!(body) do
        %{"url" => "https://x.com/example/status/1"} ->
          json_response(%{"url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg"})

        %{"url" => "https://x.com/JennerItGirls/status/2057529104535023815"} ->
          json_response(%{
            "status" => "picker",
            "picker" => [
              %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-1.jpg"},
              %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-2.jpg"},
              %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-3.jpg"},
              %{"url" => "http://127.0.0.1:#{port}/downloaded/photo-4.jpg"}
            ]
          })

        %{"url" => "https://example.com/unavailable"} ->
          error_response(%{"error" => "unsupported url"})

        %{"url" => "http://127.0.0.1:" <> _rest} ->
          error_response(%{"error" => "unsupported url"})

        unexpected ->
          raise "Unexpected cobalt request body: #{inspect(unexpected)}"
      end
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
