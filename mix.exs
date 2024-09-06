defmodule SaveIt.MixProject do
  use Mix.Project

  def project do
    [
      app: :save_it,
      version: "0.1.0",
      deps: deps(),
      start_permanent: Mix.env() == :prod
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SaveIt.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_gram, "~> 0.53"},
      {:tesla, "~> 1.11"},
      {:hackney, "~> 1.12"},
      {:jason, "~> 1.4.1"}
    ]
  end
end
