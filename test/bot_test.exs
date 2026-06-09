defmodule SaveIt.BotTest do
  use ExUnit.Case, async: false

  alias ExGram.Adapter.Test, as: ExGramTestAdapter
  alias SaveIt.Bot
  alias SaveIt.FileHelper

  setup do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    previous_ex_gram = Application.get_all_env(:ex_gram)
    previous_save_it = Application.get_all_env(:save_it)
    previous_small_sdk_telegram = Application.get_env(:tesla, SmallSdk.Telegram)
    previous_google_drive = Application.get_env(:tesla, SaveIt.GoogleDrive)

    unless Process.whereis(SaveIt.Delivery) do
      start_supervised!(SaveIt.Delivery)
    end

    Application.put_env(:ex_gram, :adapter, ExGram.Adapter.Test)
    Application.put_env(:ex_gram, :token, "test-token")
    Application.put_env(:save_it, :cobalt_api_url, base_url)
    Application.put_env(:save_it, :test_pid, self())
    Application.put_env(:save_it, :telegram_bot_token, "test-token")
    Application.put_env(:save_it, :typesense_url, base_url)
    Application.put_env(:save_it, :typesense_api_key, "test-typesense-key")

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
      restore_env(:tesla, SaveIt.GoogleDrive, previous_google_drive)
      restore_env(:ex_gram, previous_ex_gram)
      restore_env(:save_it, previous_save_it)
    end)

    %{base_url: base_url}
  end

  test "stores the original user-sent url when indexing a downloaded photo", %{base_url: base_url} do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = base_url <> "/downloaded/photo.jpg"
    cached_file_name = "bot-original-url-test.jpg"
    cached_file_content = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    FileHelper.write_file(cached_file_name, cached_file_content, download_url)

    on_exit(fn ->
      cleanup_cached_file(download_url, cached_file_name)
    end)

    message = %{
      chat: %{id: 12_345},
      message_id: 99
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}
    assert Jason.decode!(cobalt_body) == %{"url" => "https://x.com/example/status/1"}

    assert_receive {:test_http_request, :post, "/collections/photos/documents", typesense_body}

    document = Jason.decode!(typesense_body)

    assert document["url"] == original_url
    assert document["download_url"] == download_url
    assert document["file_id"] == "telegram-photo-file-id"
    assert document["belongs_to_id"] == "12345"
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
      chat: %{id: 12_345},
      message_id: 100
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    assert_receive {:test_http_request, :post, "/", cobalt_body}

    assert Jason.decode!(cobalt_body) == %{
             "url" => "https://x.com/JennerItGirls/status/2057529104535023815"
           }

    assert_receive {:telegram_media_group_request, _conn}

    documents =
      Enum.map(1..4, fn _ ->
        assert_receive {:test_http_request, :post, "/collections/photos/documents",
                        typesense_body}

        Jason.decode!(typesense_body)
      end)

    assert Enum.map(documents, & &1["url"]) == List.duplicate(original_url, 4)

    assert Enum.map(documents, & &1["download_url"]) |> Enum.sort() ==
             [
               "#{base_test_server_url()}/downloaded/photo-1.jpg",
               "#{base_test_server_url()}/downloaded/photo-2.jpg",
               "#{base_test_server_url()}/downloaded/photo-3.jpg",
               "#{base_test_server_url()}/downloaded/photo-4.jpg"
             ]
             |> Enum.sort()

    assert Enum.map(documents, & &1["file_id"]) == [
             "group-file-1",
             "group-file-2",
             "group-file-3",
             "group-file-4"
           ]
  end

  test "keeps the original user message when sending to Telegram fails", _context do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    chat_id = 12_345
    original_message_id = 101

    ExGramTestAdapter.backdoor_request("/sendPhoto", {:error, :telegram_failed})

    message = %{
      chat: %{id: chat_id},
      message_id: original_message_id
    }

    assert is_nil(Bot.handle({:text, original_url, message}, nil))

    refute {:post, "/bottest-token/deleteMessage",
            %{chat_id: chat_id, message_id: original_message_id}} in exgram_calls()
  end

  test "updates progress message when Google Drive upload fails for a logged-in user", _context do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    chat_id = 12_347

    FileHelper.set_google_access_token(chat_id, "google-access-token")
    FileHelper.set_google_drive_folder_id(chat_id, "google-folder-id")
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveFailureAdapter)

    on_exit(fn ->
      cleanup_google_settings(chat_id)
    end)

    message = %{
      chat: %{id: chat_id},
      message_id: 102
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    refute {:post, "/bottest-token/sendMessage",
            %{chat_id: chat_id, text: "💔 Failed to upload file to Google Drive."}} in exgram_calls()

    refute {:post, "/bottest-token/sendMessage",
            %{chat_id: chat_id, text: "Send to google drive failed, upload failed"}} in exgram_calls()

    assert edited_message_body().text ==
             "Searching 🔎\nDownloading 💦\nUploading 💭\nSend to google drive failed, upload failed"
  end

  test "updates progress message when Telegram upload is too large", %{base_url: base_url} do
    direct_url = base_url <> "/downloaded/oversized.mp4"
    chat_id = 12_350
    cached_file_name = "oversized.mp4"

    write_oversized_cached_file(direct_url, cached_file_name)

    on_exit(fn ->
      cleanup_cached_file(direct_url, cached_file_name)
    end)

    message = %{
      chat: %{id: chat_id},
      message_id: 105
    }

    assert is_nil(Bot.handle({:text, direct_url, message}, nil))

    refute {:post, "/bottest-token/sendMessage",
            %{chat_id: chat_id, text: "💔 File is too large for Telegram Bot API upload."}} in exgram_calls()

    refute {:post, "/bottest-token/sendMessage",
            %{
              chat_id: chat_id,
              text: "Send to telegram failed, file is too large for Telegram Bot API upload."
            }} in exgram_calls()

    assert edited_message_body().text ==
             "Searching 🔎\nDownloading 💦\nUploading 💭\nSend to telegram failed, file is too large for Telegram Bot API upload."
  end

  test "starts Telegram and Google Drive delivery in parallel after download", _context do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    chat_id = 12_349

    FileHelper.set_google_access_token(chat_id, "google-access-token")
    FileHelper.set_google_drive_folder_id(chat_id, "google-folder-id")
    Application.put_env(:ex_gram, :adapter, __MODULE__.BlockingTelegramAdapter)
    Application.put_env(:save_it, :test_pid, self())
    Application.put_env(:tesla, SaveIt.GoogleDrive, adapter: __MODULE__.GoogleDriveSuccessAdapter)

    on_exit(fn ->
      cleanup_google_settings(chat_id)
    end)

    message = %{
      chat: %{id: chat_id},
      message_id: 104
    }

    task = Task.async(fn -> Bot.handle({:text, original_url, message}, nil) end)

    assert_receive {:telegram_send_started, telegram_request_pid}
    assert_receive {:google_drive_request, _env}, 200

    send(telegram_request_pid, :release_telegram_send)

    assert {:ok, true} = Task.await(task)
  end

  test "does not notify Telegram when Google Drive upload is skipped for a user without Google login",
       _context do
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    chat_id = 12_348

    cleanup_google_settings(chat_id)

    message = %{
      chat: %{id: chat_id},
      message_id: 103
    }

    assert {:ok, true} = Bot.handle({:text, original_url, message}, nil)

    refute {:post, "/bottest-token/sendMessage",
            %{chat_id: chat_id, text: "💔 Failed to upload file to Google Drive."}} in exgram_calls()
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
              %{chat_id: 12_346, photo: "single-similar-file", caption: "single similar"}} ->
               true

             _ ->
               false
           end)

    refute Enum.any?(calls, fn
             {:post, "/bottest-token/sendMediaGroup", _body} -> true
             _ -> false
           end)
  end

  test "returns details for a replied photo", _context do
    ExGramTestAdapter.backdoor_request("/sendMessage", %{message_id: 30})

    chat_id = 12_345
    original_url = "https://x.com/example/status/1?utm_source=telegram"
    download_url = "#{base_test_server_url()}/downloaded/photo.jpg"

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
    assert request_body.text =~ "Sent at: 2024-06-01 00:00:00 UTC"
    assert request_body.text =~ "Original URL: #{original_url}"
    assert request_body.text =~ "Download URL: #{download_url}"
    assert request_body.text =~ "File ID: telegram-photo-file-id"
  end

  defp cleanup_cached_file(download_url, cached_file_name) do
    hashed_url = :crypto.hash(:sha256, download_url) |> Base.url_encode64(padding: false)
    url_cache_path = Path.join(["./data/storage/urls", hashed_url])
    file_path = Path.join(["./data/storage/files", cached_file_name])

    File.rm(url_cache_path)
    File.rm(file_path)
  end

  defp base_test_server_url do
    Application.fetch_env!(:save_it, :typesense_url)
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

  defp edited_message_body do
    %{calls: calls} = :sys.get_state(ExGram.Adapter.Test)

    calls
    |> Enum.reverse()
    |> Enum.find_value(fn
      {:post, path, body} ->
        if String.ends_with?(path, "/editMessageText"), do: body

      _ ->
        nil
    end)
  end

  defp write_oversized_cached_file(download_url, cached_file_name) do
    FileHelper.write_file(cached_file_name, <<0>>, download_url)

    file_path = Path.join(["./data/storage/files", cached_file_name])
    {:ok, file} = File.open(file_path, [:write, :binary])
    {:ok, _position} = :file.position(file, 50 * 1024 * 1024)
    :ok = IO.binwrite(file, <<0>>)
    :ok = File.close(file)
  end

  defp cleanup_cached_folder(cache_key_url) do
    hashed_url = :crypto.hash(:sha256, cache_key_url) |> Base.url_encode64(padding: false)
    url_cache_path = Path.join(["./data/storage/urls", hashed_url])
    files_dir_path = Path.join(["./data/storage/files", hashed_url])

    File.rm(url_cache_path)
    File.rm_rf(files_dir_path)
  end

  defp cleanup_google_settings(chat_id) do
    File.rm_rf(Path.join(["./data/settings", to_string(chat_id)]))
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

  defmodule TelegramMediaGroupAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(Application.fetch_env!(:save_it, :test_pid), {:telegram_media_group_request, env})

      {:ok,
       %Tesla.Env{
         env
         | status: 200,
           body: %{
             "ok" => true,
             "result" => [
               %{"photo" => [%{"file_id" => "group-file-1"}]},
               %{"photo" => [%{"file_id" => "group-file-2"}]},
               %{"photo" => [%{"file_id" => "group-file-3"}]},
               %{"photo" => [%{"file_id" => "group-file-4"}]}
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

  defmodule GoogleDriveFailureAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(self(), {:google_drive_request, env})

      {:ok,
       %Tesla.Env{
         env
         | status: 500,
           body: %{"error" => %{"message" => "upload failed"}}
       }}
    end
  end

  defmodule GoogleDriveSuccessAdapter do
    @behaviour Tesla.Adapter

    @impl Tesla.Adapter
    def call(%Tesla.Env{} = env, _opts) do
      send(Application.fetch_env!(:save_it, :test_pid), {:google_drive_request, env})

      {:ok,
       %Tesla.Env{
         env
         | status: 200,
           body: %{"id" => "google-drive-file-id"}
       }}
    end
  end

  defmodule BlockingTelegramAdapter do
    @behaviour ExGram.Adapter

    @impl ExGram.Adapter
    def request(:post, "/bottest-token/sendMessage", _body) do
      {:ok, %{message_id: 10}}
    end

    def request(:post, "/bottest-token/editMessageText", _body) do
      {:ok, %{message_id: 10}}
    end

    def request(:post, "/bottest-token/deleteMessage", _body) do
      {:ok, true}
    end

    def request(:post, "/bottest-token/sendPhoto", _body) do
      send(Application.fetch_env!(:save_it, :test_pid), {:telegram_send_started, self()})

      receive do
        :release_telegram_send ->
          {:ok, %{message_id: 20, photo: [%{file_id: "telegram-photo-file-id"}]}}
      after
        2_000 ->
          {:error, %ExGram.Error{message: "telegram send was not released"}}
      end
    end

    def request(:get, "/bottest-token/getUpdates", _body) do
      {:ok, []}
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

        unexpected ->
          raise "Unexpected cobalt request body: #{inspect(unexpected)}"
      end
    end

    defp response_for("/collections/photos/documents/search?" <> _query, port, _body) do
      json_response(%{
        "hits" => [
          %{
            "document" => %{
              "id" => "typesense-photo-id",
              "caption" => "",
              "file_id" => "telegram-photo-file-id",
              "url" => "https://x.com/example/status/1?utm_source=telegram",
              "download_url" => "http://127.0.0.1:#{port}/downloaded/photo.jpg",
              "belongs_to_id" => "12345",
              "inserted_at" => 1_717_200_000
            }
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
