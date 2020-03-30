defmodule Marshale.MixProject do
  use Mix.Project

  def project do
    [
      app: :marshale,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),

      # Docs
      name: "marshale",
      source_url: "https://github.com/A5rocks/marshale",
      homepage_url: "https://a5rocks.github.io/marshale",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["A5rocks"],
      licenses: ["BSD 3-Clause"],
      links: %{"GitHub" => "https://github.com/A5rocks/marshale"}
    ]
  end
end
