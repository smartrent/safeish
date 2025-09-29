defmodule Safeish.MixProject do
  use Mix.Project

  def project do
    [
      app: :safeish,
      version: "0.5.2",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      source_url: "https://github.com/robinhilliard/safeish"
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
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: [:test, :dev], runtime: false},
      {:spellweaver, "~> 0.1.0", only: [:test, :dev], runtime: false}
    ]
  end

  defp description() do
    "NOT FOR PRODUCTION USE: Safe-ish is an experimental sandbox for BEAM modules that examines and rejects BEAM bytecode containing instructions that could cause side effects. You can provide an optional whitelist of opcodes and functions the module can use."
  end

  defp package() do
    [
      name: "safeish",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      exclude_patterns: [".DS_Store"],
      licenses: ["MIT"],
      maintainers: ["Jean-Francois Cloutier"],
      links: %{
        "GitHub" => "https://github.com/smartrent/safeish"
      },
      organization: "smartrent"
    ]
  end

  defp dialyzer() do
    ci_opts =
      if System.get_env("CI") do
        [plt_core_path: "_build/plts", plt_local_path: "_build/plts"]
      else
        []
      end

    [
      flags: [:unmatched_returns, :error_handling, :missing_return, :extra_return]
    ] ++ ci_opts
  end

  defp aliases, do: [fixtures: &make_fixtures/1]

  defp make_fixtures(_) do
    source_path = "#{File.cwd!()}/test/fixtures.ex"
    build_path = "#{File.cwd!()}/test/fixtures_build"

    Mix.Shell.IO.info("Compiling modules in #{source_path} and saving to #{build_path}")

    File.rm_rf(build_path)
    File.mkdir(build_path)

    for {module, bytecode} <- Code.compile_file(source_path) do
      Mix.Shell.IO.info("...#{build_path}/#{Atom.to_string(module)}.beam")
      {:ok, file} = File.open("#{build_path}/#{Atom.to_string(module)}.beam", [:write])
      IO.binwrite(file, bytecode)
      File.close(file)
    end
  end
end
