defmodule AierBotTest do
  use ExUnit.Case
  doctest AierBot

  test "greets the world" do
    assert AierBot.hello() == :world
  end
end
