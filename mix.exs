defmodule SaveIt.MixProject do
  use Mix.Project

  def project do
    [
      app: :save_it,
      version: "0.2.0-rc.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, ex_unit: :optional],
      mod: {SaveIt.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_gram, "~> 0.53"},
      {:tesla, "~> 1.11"},
      {:hackney, "~> 1.12"},
      {:jason, "~> 1.4.1"},
      {:req, "~> 0.5.0"}
    ]
  end
end
