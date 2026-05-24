defmodule SaveItTest do
  use ExUnit.Case
  doctest SaveIt

  test "greets the world" do
    assert SaveIt.hello() == :world
  end
end
