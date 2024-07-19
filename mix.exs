defmodule AierBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :aier_bot,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AierBot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_gram, "~> 0.40.0"},
      {:tesla, "~> 1.7.0"},
      {:openai_ex, "~> 0.3.0"},
      {:hackney, "~> 1.18.2"},
      {:jason, ">= 1.4.1"}
    ]
  end
end
