defmodule SmallSdk.LinkPreviewTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  import ExUnit.CaptureLog

  alias SmallSdk.LinkPreview

  setup do
    previous_save_it = Application.get_all_env(:save_it)

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "extracts a GitHub profile og image" do
    html = """
    <html>
      <head>
        <meta property="og:image" content="https://avatars.githubusercontent.com/u/17308201?v=4?s=400" />
      </head>
    </html>
    """

    assert LinkPreview.get_image_url_from_html(
             "https://github.com/Thaddeusjiang",
             html
           ) ==
             {:ok, "https://avatars.githubusercontent.com/u/17308201?v=4?s=400"}
  end

  test "extracts a Scrapbox project og image" do
    html = """
    <html>
      <head>
        <meta property="og:image" content="https://gyazo.com/e3f4b97ec5d43ec64ef4fd112c658017/max_size/2000"/>
      </head>
    </html>
    """

    assert LinkPreview.get_image_url_from_html(
             "https://scrapbox.io/ThaddeusJiang/",
             html
           ) ==
             {:ok, "https://gyazo.com/e3f4b97ec5d43ec64ef4fd112c658017/max_size/2000"}
  end

  test "extracts an og description" do
    html = """
    <html>
      <head>
        <meta property="og:description" content="Photo Page OG Description" />
      </head>
    </html>
    """

    assert LinkPreview.get_description_from_html(html) == {:ok, "Photo Page OG Description"}
  end

  test "extracts an og title" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="YouTube Page OG Title" />
      </head>
    </html>
    """

    assert LinkPreview.get_title_from_html(html) == {:ok, "YouTube Page OG Title"}
  end

  test "extracts preview metadata from html" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="Preview Page OG Title" />
        <meta property="og:description" content="Preview Page OG Description" />
        <meta name="keywords" content="alpha, beta , ,gamma" />
        <meta property="og:image" content="/preview.jpg" />
      </head>
    </html>
    """

    assert LinkPreview.get_metadata_from_html("https://example.com/posts/1", html) == %{
             title: "Preview Page OG Title",
             description: "Preview Page OG Description",
             keywords: ["alpha", "beta", "gamma"],
             image_url: "https://example.com/preview.jpg"
           }
  end

  test "logs fetched preview metadata with sanitized page URL" do
    html = """
    <html>
      <head>
        <meta property="og:title" content="Logged Page OG Title" />
        <meta property="og:description" content="Logged Page OG Description" />
        <meta name="keywords" content="logged, metadata" />
        <meta property="og:image" content="/logged-preview.jpg" />
      </head>
    </html>
    """

    server = start_supervised!({__MODULE__.TestHttpServer, html: html})
    page_url = "http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}/page?token=secret"

    previous_level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log([level: :debug], fn ->
          assert {:ok, _metadata} = LinkPreview.get_metadata(page_url)
        end)
      after
        Logger.configure(level: previous_level)
      end

    assert log =~ "Link preview metadata fetched"
    assert log =~ ~s(page_url="http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}/page")
    assert log =~ ~s(og_title="Logged Page OG Title")
    assert log =~ ~s(og_description="Logged Page OG Description")
    assert log =~ ~s(keywords="logged, metadata")

    assert log =~
             ~s(og_image="http://127.0.0.1:#{__MODULE__.TestHttpServer.port(server)}/logged-preview.jpg")

    refute log =~ "token=secret"
  end

  test "uses authenticated X metadata when cobalt cookies are available", %{tmp_dir: tmp_dir} do
    cookie_path = Path.join(tmp_dir, "cobalt-cookies.json")

    File.write!(
      cookie_path,
      Jason.encode!(%{
        "twitter" => ["auth_token=fake-auth; ct0=fake-csrf; guest_id=fake-guest"]
      })
    )

    server = start_supervised!({__MODULE__.XApiServer, test_pid: self()})
    base_url = "http://127.0.0.1:#{__MODULE__.XApiServer.port(server)}"

    Application.put_env(:save_it, :cobalt_cookies_path, cookie_path)
    Application.put_env(:save_it, :x_api_base_url, base_url)
    Application.put_env(:save_it, :x_bearer_token, "test-bearer")
    Application.put_env(:save_it, :x_tweet_result_query_id, "test-query")

    assert {:ok, metadata} =
             LinkPreview.get_metadata("https://x.com/Yoga_mjao_/status/2065289899558019496?s=20")

    assert metadata.title == "Yoga Cat (@Yoga_mjao_) on X"
    assert metadata.description == "real tweet text #alpha #beta"
    assert metadata.keywords == ["alpha", "beta"]
    assert metadata.image_url == "https://pbs.twimg.com/media/example.jpg"

    assert_receive {:x_request, request}
    assert request =~ "GET /i/api/graphql/test-query/TweetResultByRestId?"
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

    defstruct [:listen_socket, :port, :html, :acceptor_pid]

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def port(server), do: GenServer.call(server, :port)

    def init(opts) do
      {:ok, listen_socket} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listen_socket)
      html = Keyword.fetch!(opts, :html)

      {:ok, acceptor_pid} =
        Task.start_link(fn ->
          accept_loop(listen_socket, html)
        end)

      {:ok,
       %__MODULE__{
         listen_socket: listen_socket,
         port: port,
         html: html,
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

    defp accept_loop(listen_socket, html) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, socket} ->
          {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)
          :gen_tcp.send(socket, html_response(html))
          :gen_tcp.close(socket)
          accept_loop(listen_socket, html)

        {:error, :closed} ->
          :ok
      end
    end

    defp html_response(html) do
      """
      HTTP/1.1 200 OK\r
      content-type: text/html\r
      content-length: #{byte_size(html)}\r
      connection: close\r
      \r
      #{html}
      """
    end
  end

  defmodule XApiServer do
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
          {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
          send(test_pid, {:x_request, request})
          :gen_tcp.send(socket, json_response())
          :gen_tcp.close(socket)
          accept_loop(listen_socket, test_pid)

        {:error, :closed} ->
          :ok
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
