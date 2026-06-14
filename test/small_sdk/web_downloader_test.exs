defmodule SmallSdk.WebDownloaderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SmallSdk.WebDownloader

  test "does not log successful downloads at the default level" do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    port = GenServer.call(server, :port)

    log =
      capture_log(fn ->
        assert {:ok, downloaded_file} =
                 WebDownloader.download_file("http://127.0.0.1:#{port}/photo.jpg")

        assert downloaded_file.file_content == "file-bytes"
      end)

    refute log =~ "download_file started"
    refute log =~ "download_file succeeded"
  end

  defmodule TestHttpServer do
    use GenServer

    defstruct [:listen_socket, :port, :acceptor_pid]

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts) do
      {:ok, listen_socket} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen_socket)
      test_pid = Keyword.fetch!(opts, :test_pid)

      {:ok, acceptor_pid} =
        Task.start_link(fn ->
          accept_loop(listen_socket, test_pid)
        end)

      {:ok, %__MODULE__{listen_socket: listen_socket, port: port, acceptor_pid: acceptor_pid}}
    end

    @impl GenServer
    def handle_call(:port, _from, %{port: port} = state), do: {:reply, port, state}

    @impl GenServer
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
      {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
      [request_line | _] = String.split(request, "\r\n")
      ["GET", path, _] = String.split(request_line, " ")
      send(test_pid, {:test_http_request, :get, path})
      :gen_tcp.send(socket, response())
      :gen_tcp.close(socket)
    end

    defp response do
      body = "file-bytes"

      """
      HTTP/1.1 200 OK\r
      content-type: image/jpeg\r
      content-length: #{byte_size(body)}\r
      connection: close\r
      \r
      #{body}
      """
    end
  end
end
