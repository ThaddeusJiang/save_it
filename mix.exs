defmodule SaveIt.MixProject do
  use Mix.Project

  def project do
    [
      app: :save_it,
      version: "0.4.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def cli do
    [
      preferred_envs: [
        quality: :dev
      ]
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
      {:sentry, "~> 10.2.0"},
      {:hackney, "~> 1.12"},
      {:jason, "~> 1.4.1"},
      {:req, "~> 0.5.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end
end
