defmodule SaveIt.MixProject do
  use Mix.Project

  def project do
    [
      app: :save_it,
      version: "2026.6.13",
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
        checks: :dev
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
      {:ex_gram, "0.67.0"},
      {:sentry, "13.2.0"},
      {:jason, "1.4.5"},
      {:req, "0.5.18"},
      {:tzdata, "1.1.3"},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.3", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      checks: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end
end
