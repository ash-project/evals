defmodule Evals.MixProject do
  use Mix.Project

  def project do
    [
      app: :evals,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix]
      ],
      deps: deps()
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:langchain, "~> 0.3"},
      {:yaml_elixir, "~> 2.0"},
      {:spark, "~> 2.2"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:mock, "~> 0.3.9", only: :test},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.5", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      credo: "credo --strict"
    ]
  end
end
