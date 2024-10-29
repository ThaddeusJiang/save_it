defmodule SaveItTest do
  use ExUnit.Case
  doctest SaveIt

  doctest SaveIt.Migration.Typesense.Photo

  test "greets the world" do
    assert SaveIt.hello() == :world
  end
end
