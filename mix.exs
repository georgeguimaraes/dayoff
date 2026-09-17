defmodule Dayoff.MixProject do
  use Mix.Project

  @version "0.2.2"
  @source_url "https://github.com/georgeguimaraes/dayoff"

  def project do
    [
      app: :dayoff,
      name: "Dayoff",
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [docs: :docs, "hex.publish": :docs]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # The sync task drives Node scripts and is only for maintaining this repo.
  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib"]
  defp elixirc_paths(_env), do: ["lib/dayoff", "lib/dayoff.ex"]

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["George Guimarães"],
      description:
        "Public holidays for 200+ countries, states and regions, offline, from the date-holidays dataset.",
      licenses: ["Apache-2.0"],
      files: ~w(lib/dayoff lib/dayoff.ex priv mix.exs README.md LICENSE NOTICE CHANGELOG.md),
      links: %{
        "GitHub" => @source_url,
        "Upstream data" => "https://github.com/commenthol/date-holidays"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      authors: ["George Guimarães"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      before_closing_body_tag: fn _format ->
        """
        <footer style="padding: 1rem 0; margin-top: 2rem; border-top: 1px solid #e1e4e8; font-size: 0.875rem; color: #586069;">
          Copyright 2026 George Guimarães. Licensed under Apache-2.0. Holiday data by commenthol/date-holidays, CC BY-SA 3.0.
        </footer>
        """
      end,
      extras: [
        "README.md",
        "guides/rules.md"
      ],
      groups_for_extras: [
        Guides: ["guides/rules.md"]
      ]
    ]
  end
end
