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

    Application.put_env(:ex_gram, :adapter, ExGram.Adapter.Test)
    Application.put_env(:ex_gram, :token, "test-token")
    Application.put_env(:save_it, :cobalt_api_url, base_url)
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
               %{"photo" => [%{"file_id" => "group-file-1"}]},
               %{"photo" => [%{"file_id" => "group-file-2"}]},
               %{"photo" => [%{"file_id" => "group-file-3"}]},
               %{"photo" => [%{"file_id" => "group-file-4"}]}
             ]
           }
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

        unexpected ->
          raise "Unexpected cobalt request body: #{inspect(unexpected)}"
      end
    end

    defp response_for("/collections/photos/documents", _port, _body) do
      json_response(%{"id" => "typesense-photo-id"})
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

      content_length =
        header_lines
        |> Enum.find_value(0, fn line ->
          case String.split(line, ":", parts: 2) do
            [name, value] ->
              if String.downcase(name) == "content-length" do
                value |> String.trim() |> String.to_integer()
              end

            _ ->
              nil
          end
        end)

      body = read_body(socket, body_prefix, content_length)

      {String.downcase(method) |> String.to_atom(), path, body}
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
