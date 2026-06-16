defmodule SmallSdk.XMetadataTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias SmallSdk.XMetadata

  setup %{tmp_dir: tmp_dir} do
    previous_save_it = Application.get_all_env(:save_it)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    cookie_path = Path.join(tmp_dir, "cobalt-cookies.json")

    File.write!(
      cookie_path,
      Jason.encode!(%{
        "twitter" => ["auth_token=fake-auth; ct0=fake-csrf; guest_id=fake-guest"]
      })
    )

    Application.put_env(:save_it, :cobalt_cookies_path, cookie_path)
    Application.put_env(:save_it, :x_bearer_token, "test-bearer")
    Application.put_env(:save_it, :x_tweet_result_query_id, "test-query")

    :ok
  end

  test "fetches authenticated X metadata from cobalt cookies" do
    server = start_supervised!({__MODULE__.TestHttpServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}"

    Application.put_env(:save_it, :x_api_base_url, base_url)

    assert {:ok, metadata} =
             XMetadata.get_metadata("https://x.com/Yoga_mjao_/status/2065289899558019496?s=20")

    assert metadata == %{
             title: "Yoga Cat (@Yoga_mjao_) on X",
             description: "real tweet text #alpha #beta",
             keywords: ["alpha", "beta"],
             image_url: "https://pbs.twimg.com/media/example.jpg"
           }

    assert_receive {:x_request, request}
    assert request =~ "GET /i/api/graphql/test-query/TweetResultByRestId?"
    assert request =~ "authorization: Bearer test-bearer"
    assert request =~ "cookie: auth_token=fake-auth; ct0=fake-csrf; guest_id=fake-guest"
    assert request =~ "x-csrf-token: fake-csrf"
    assert request =~ "tweetId%22%3A%222065289899558019496"
  end

  test "returns an error when cobalt cookies are missing" do
    Application.put_env(:save_it, :cobalt_cookies_path, "/missing/cobalt-cookies.json")

    assert {:error, :missing_twitter_cookie} =
             XMetadata.get_metadata("https://x.com/Yoga_mjao_/status/2065289899558019496")
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

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def port(server), do: GenServer.call(server, :port)

    def init(opts) do
      {:ok, listen_socket} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen_socket)
      test_pid = Keyword.fetch!(opts, :test_pid)

      {:ok, acceptor_pid} =
        Task.start_link(fn ->
          accept_loop(listen_socket, test_pid)
        end)

      {:ok,
       %__MODULE__{
         listen_socket: listen_socket,
         port: port,
         test_pid: test_pid,
         acceptor_pid: acceptor_pid
       }}
    end

    def handle_call(:port, _from, %{port: port} = state), do: {:reply, port, state}

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
          {:ok, request} = recv_request(socket)
          send(test_pid, {:x_request, request})
          :gen_tcp.send(socket, json_response())
          :gen_tcp.close(socket)
          accept_loop(listen_socket, test_pid)

        {:error, :closed} ->
          :ok
      end
    end

    defp recv_request(socket, acc \\ "") do
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, chunk} ->
          request = acc <> chunk

          if String.contains?(request, "\r\n\r\n") do
            {:ok, request}
          else
            recv_request(socket, request)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp json_response do
      body =
        %{
          "data" => %{
            "tweetResult" => %{
              "result" => %{
                "__typename" => "TweetWithVisibilityResults",
                "tweet" => %{
                  "core" => %{
                    "user_results" => %{
                      "result" => %{
                        "core" => %{
                          "name" => "Yoga Cat",
                          "screen_name" => "Yoga_mjao_"
                        }
                      }
                    }
                  },
                  "legacy" => %{
                    "full_text" => "real tweet text #alpha #beta",
                    "entities" => %{
                      "hashtags" => [
                        %{"text" => "alpha"},
                        %{"text" => "beta"}
                      ]
                    },
                    "extended_entities" => %{
                      "media" => [
                        %{
                          "type" => "photo",
                          "media_url_https" => "https://pbs.twimg.com/media/example.jpg"
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
        |> Jason.encode!()

      """
      HTTP/1.1 200 OK\r
      content-type: application/json\r
      content-length: #{byte_size(body)}\r
      connection: close\r
      \r
      #{body}
      """
    end
  end
end
