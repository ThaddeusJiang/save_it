defmodule SaveIt.PhotoServiceTest do
  use ExUnit.Case, async: false

  alias SaveIt.PhotoService

  setup do
    previous_url = Application.get_env(:save_it, :typesense_url)
    previous_api_key = Application.get_env(:save_it, :typesense_api_key)

    {:ok, server} = __MODULE__.TestHttpServer.start_link(test_pid: self())
    port = __MODULE__.TestHttpServer.port(server)

    Application.put_env(:save_it, :typesense_url, "http://127.0.0.1:#{port}")
    Application.put_env(:save_it, :typesense_api_key, "test-typesense-key")

    on_exit(fn ->
      restore_env(:typesense_url, previous_url)
      restore_env(:typesense_api_key, previous_api_key)
    end)

    :ok
  end

  test "search_photos returns caption matches before high-confidence image semantic matches" do
    assert [
             %{"id" => "caption-result"},
             %{"id" => "shared-result"},
             %{"id" => "image-result"}
           ] =
             PhotoService.search_photos!("summer beach", belongs_to_id: 12_345)

    assert_receive {:test_http_request, :post, "/multi_search", body}

    assert %{
             "searches" => [
               %{
                 "collection" => "photos",
                 "q" => "summer beach",
                 "query_by" => "caption,title,description,keywords",
                 "filter_by" => "belongs_to_id:=12345",
                 "prefix" => true,
                 "drop_tokens_threshold" => 0,
                 "exclude_fields" => "image_embedding"
               },
               %{
                 "collection" => "photos",
                 "q" => "summer beach",
                 "query_by" => "image_embedding",
                 "filter_by" => "belongs_to_id:=12345",
                 "prefix" => false,
                 "vector_query" => "image_embedding:([], k: 20, distance_threshold: 0.775)",
                 "drop_tokens_threshold" => 0,
                 "exclude_fields" => "image_embedding"
               }
             ]
           } = Jason.decode!(body)
  end

  defp restore_env(key, nil), do: Application.delete_env(:save_it, key)
  defp restore_env(key, value), do: Application.put_env(:save_it, key, value)

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
          accept_loop(list_socket: listen_socket, test_pid: test_pid)
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

    defp accept_loop(list_socket: listen_socket, test_pid: test_pid) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, socket} ->
          handle_socket(socket, test_pid)
          accept_loop(list_socket: listen_socket, test_pid: test_pid)

        {:error, :closed} ->
          :ok
      end
    end

    defp handle_socket(socket, test_pid) do
      {method, path, body} = read_http_request(socket)
      send(test_pid, {:test_http_request, method, path, body})
      :gen_tcp.send(socket, json_response(%{"results" => search_results()}))
      :gen_tcp.close(socket)
    end

    defp search_results do
      [
        %{
          "hits" => [
            %{
              "document" => %{
                "id" => "caption-result",
                "caption" => "summer beach",
                "file_id" => "caption-file-id"
              }
            },
            %{
              "document" => %{
                "id" => "shared-result",
                "caption" => "shared caption",
                "file_id" => "shared-file-id"
              }
            }
          ]
        },
        %{
          "hits" => [
            %{
              "document" => %{
                "id" => "shared-result",
                "caption" => "shared image",
                "file_id" => "shared-file-id"
              }
            },
            %{
              "document" => %{
                "id" => "image-result",
                "caption" => "image match",
                "file_id" => "image-file-id"
              }
            }
          ]
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
