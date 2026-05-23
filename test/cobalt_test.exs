defmodule SmallSdk.CobaltTest do
  use ExUnit.Case, async: true

  alias SmallSdk.Cobalt

  test "handle_response/1 returns ok for success status" do
    response = {:ok, %{status: 200, body: %{"url" => "https://example.com/a.jpg"}}}

    assert {:ok, %{"url" => "https://example.com/a.jpg"}} = Cobalt.handle_response(response)
  end

  test "handle_response/1 returns error tuple for non-2xx status" do
    response = {:ok, %{status: 500, body: %{"error" => "internal"}}}

    assert {:error, msg} = Cobalt.handle_response(response)
    assert msg =~ "Request failed with status 500"
  end

  test "handle_response/1 does not raise on transport error" do
    response = {:error, %Req.TransportError{reason: :econnrefused}}

    assert {:error, msg} = Cobalt.handle_response(response)
    assert msg =~ "Request failed"
    assert msg =~ "econnrefused"
  end
end
