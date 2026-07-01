defmodule SaveIt.GoogleOAuth2DeviceFlowTest do
  use ExUnit.Case, async: false

  alias SaveIt.GoogleOAuth2DeviceFlow

  setup do
    previous_save_it = Application.get_all_env(:save_it)

    Application.put_env(:save_it, :google_oauth_client_id, "client-id")
    Application.put_env(:save_it, :google_oauth_client_secret, "client-secret")

    Application.put_env(:save_it, :google_oauth_req_options,
      adapter: &__MODULE__.request_adapter/1
    )

    Application.put_env(:save_it, :test_pid, self())

    on_exit(fn ->
      restore_env(:save_it, previous_save_it)
    end)

    :ok
  end

  test "requests a Google device code with a Req form request" do
    assert {:ok, %{"device_code" => "device-code"}} = GoogleOAuth2DeviceFlow.get_device_code()

    assert_receive {:google_oauth_request, request}

    assert request.method == :post
    assert URI.to_string(request.url) == "https://oauth2.googleapis.com/device/code"

    body = IO.iodata_to_binary(request.body)
    assert body =~ "client_id=client-id"
    assert body =~ "scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file"
  end

  test "does not request a device code when OAuth config is incomplete" do
    Application.put_env(:save_it, :google_oauth_client_secret, "")

    assert {:error, {:missing_config, :google_oauth_client_secret}} =
             GoogleOAuth2DeviceFlow.get_device_code()

    refute_receive {:google_oauth_request, _request}
  end

  test "exchanges a device code with a Req form request" do
    assert {:ok, %{"access_token" => "access-token"}} =
             GoogleOAuth2DeviceFlow.exchange_device_code_for_token("device-code")

    assert_receive {:google_oauth_request, request}

    assert request.method == :post
    assert URI.to_string(request.url) == "https://oauth2.googleapis.com/token"

    body = IO.iodata_to_binary(request.body)
    assert body =~ "client_id=client-id"
    assert body =~ "client_secret=client-secret"
    assert body =~ "device_code=device-code"
    assert body =~ "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
  end

  def request_adapter(request) do
    send(Application.fetch_env!(:save_it, :test_pid), {:google_oauth_request, request})

    body =
      case request.url.path do
        "/device/code" -> %{"device_code" => "device-code"}
        "/token" -> %{"access_token" => "access-token"}
      end

    {request, %Req.Response{status: 200, body: body}}
  end

  defp restore_env(app, env) do
    app
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(app, &1))

    Enum.each(env, fn {key, value} ->
      Application.put_env(app, key, value)
    end)
  end
end
