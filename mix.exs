defmodule Forge.MixProject do
  use Mix.Project

  def project do
    [
      app: :forge,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Forge.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:supertester, "~> 0.3.1", only: :test}
    ]
  end
end
