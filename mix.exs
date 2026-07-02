defmodule SaveIt.MixProject do
  use Mix.Project

  alias SmallSdk.TypesenseMigration.Runner, as: TypesenseMigrationRunner

  def project do
    [
      app: :save_it,
      version: "2026.7.2",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [
        output: "cover",
        summary: [threshold: 50]
      ],
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def cli do
    [
      preferred_envs: [
        checks: :dev,
        coverage: :test
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
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.3", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ts.migrate"],
      dev: "run --no-halt",
      reset: "cmd rm -rf data",
      coverage: "test --cover",
      "ts.migrate": &ts_migrate/1,
      "ts.rollback": &ts_rollback/1,
      "ts.reset": &ts_reset/1,
      checks: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  defp ts_migrate(args), do: run_typesense_runner(["migrate" | args])
  defp ts_rollback(args), do: run_typesense_runner(["rollback" | args])
  defp ts_reset(args), do: run_typesense_runner(["reset" | args])

  defp run_typesense_runner(args) do
    Mix.Task.run("loadpaths")
    Code.require_file("priv/typesense/runner.exs")
    TypesenseMigrationRunner.run(args)
  end
end
