defmodule SaveIt.MixProjectTest do
  use ExUnit.Case, async: true

  test "configures test coverage with a dedicated alias" do
    project = SaveIt.MixProject.project()
    aliases = Keyword.fetch!(project, :aliases)

    assert Keyword.fetch!(aliases, :coverage) == "test --cover"

    assert Keyword.fetch!(project, :test_coverage) == [
             output: "cover",
             summary: [threshold: 50]
           ]

    assert SaveIt.MixProject.cli()[:preferred_envs][:coverage] == :test
  end

  test "runs Typesense maintenance commands without compiling the application" do
    aliases = SaveIt.MixProject.project() |> Keyword.fetch!(:aliases)

    assert aliases |> Keyword.fetch!(:"ts.migrate") |> is_function(1)
    assert aliases |> Keyword.fetch!(:"ts.rollback") |> is_function(1)
    assert aliases |> Keyword.fetch!(:"ts.reset") |> is_function(1)
  end
end
