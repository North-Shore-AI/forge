defmodule Forge.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/forge"

  def project do
    [
      app: :forge,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      name: "Forge",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Forge.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:supertester, "~> 0.3.1", only: :test}
    ]
  end

  defp description do
    """
    Sample factory library for generating, transforming, and computing
    measurements on arbitrary samples. Domain-agnostic data pipeline
    orchestration for ML dataset preparation.
    """
  end

  defp package do
    [
      name: "forge_ex",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["North-Shore-AI"],
      files: ~w(lib assets assets/forge.svg .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp aliases do
    [
      "forge.setup": ["ecto.create", "ecto.migrate"],
      "forge.reset": ["ecto.drop", "forge.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp docs do
    [
      main: "Forge",
      assets: %{"assets" => "assets"},
      logo: "assets/forge.svg",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Forge,
          Forge.Sample,
          Forge.Pipeline
        ],
        Behaviours: [
          Forge.Source,
          Forge.Stage,
          Forge.Measurement,
          Forge.Storage
        ],
        Sources: [
          Forge.Source.Static,
          Forge.Source.Generator
        ],
        Storage: [
          Forge.Storage.ETS
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
