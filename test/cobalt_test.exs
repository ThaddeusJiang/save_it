defmodule SmallSdk.CobaltTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SmallSdk.Cobalt

  setup do
    previous_save_it = Application.get_all_env(:save_it)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "handle_response/1 returns ok for success status" do
    response = {:ok, %{status: 200, body: %{"url" => "https://example.com/a.jpg"}}}

    assert {:ok, %{"url" => "https://example.com/a.jpg"}} = Cobalt.handle_response(response)
  end

  test "handle_response/1 returns error tuple for non-2xx status" do
    response = {:ok, %{status: 500, body: %{"error" => "internal"}}}

    assert {:error, msg} = Cobalt.handle_response(response)
    assert msg =~ "Request failed with status 500"
    refute msg =~ "internal"
    refute msg =~ "%{"
  end

  test "handle_response/1 does not raise on transport error" do
    response = {:error, %Req.TransportError{reason: :econnrefused}}

    assert {:error, msg} = Cobalt.handle_response(response)
    assert msg == "Request failed"
  end

  test "get_download_url/1 rewrites tunnel urls to the configured cobalt api host" do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    Application.put_env(:save_it, :cobalt_api_url, base_url)

    assert {:ok, download_url} =
             Cobalt.get_download_url("https://x.com/lalisa4K/status/2057481649609453909?s=20")

    assert download_url == base_url <> "/tunnel?id=abc"

    assert_receive {:test_http_request, :post, "/", body}

    assert Jason.decode!(body) == %{
             "url" => "https://x.com/lalisa4K/status/2057481649609453909"
           }
  end

  test "get_download_url/1 logs sanitized debug context" do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    Application.put_env(:save_it, :cobalt_api_url, base_url)

    previous_level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log([level: :debug], fn ->
          assert {:ok, _download_url} =
                   Cobalt.get_download_url(
                     "https://x.com/lalisa4K/status/2057481649609453909?s=20"
                   )
        end)
      after
        Logger.configure(level: previous_level)
      end

    assert log =~ "Cobalt request started"
    assert log =~ ~s(api_url="#{base_url}")
    assert log =~ ~s(source_url="https://x.com/lalisa4K/status/2057481649609453909")
    refute log =~ "s=20"
  end

  defp restore_env(app, env) do
    Application.get_all_env(app)
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
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
          accept_loop(listen_socket, test_pid)
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

    defp accept_loop(listen_socket, test_pid) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, socket} ->
          handle_socket(socket, test_pid)
          accept_loop(listen_socket, test_pid)

        {:error, :closed} ->
          :ok
      end
    end

    defp handle_socket(socket, test_pid) do
      {method, path, body} = read_http_request(socket)
      send(test_pid, {:test_http_request, method, path, body})
      :gen_tcp.send(socket, response_for(path))
      :gen_tcp.close(socket)
    end

    defp response_for("/") do
      json_response(%{
        "status" => "tunnel",
        "url" => "http://cobalt-api:9000/tunnel?id=abc",
        "filename" => "twitter_2057481649609453909.jpg"
      })
    end

    defp response_for(_path) do
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
      content_length = parse_content_length(header_lines)

      body = read_body(socket, body_prefix, content_length)

      {String.downcase(method) |> String.to_existing_atom(), path, body}
    end

    defp split_headers(data) do
      case :binary.split(data, "\r\n\r\n") do
        [headers, body] -> {headers, body}
        [headers] -> {headers, ""}
      end
    end

    defp parse_content_length(header_lines) do
      header_lines
      |> Enum.find_value(0, &content_length_from_header/1)
    end

    defp content_length_from_header(header) do
      case String.split(header, ":", parts: 2) do
        ["content-length", value] ->
          String.trim(value) |> String.to_integer()

        [name, value] ->
          if String.downcase(name) == "content-length" do
            String.trim(value) |> String.to_integer()
          end

        _ ->
          nil
      end
    end

    defp read_body(socket, body_prefix, content_length) do
      remaining = content_length - byte_size(body_prefix)

      if remaining > 0 do
        {:ok, rest} = :gen_tcp.recv(socket, remaining, 5_000)
        body_prefix <> rest
      else
        body_prefix
      end
    end
  end
end
