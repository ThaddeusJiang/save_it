# Credo configuration kept intentionally small so the project starts
# with community defaults and can tighten rules incrementally.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true
    }
  ]
}
