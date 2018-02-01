%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/"],
        excluded: []
      },
      checks: [
        {Credo.Check.Readability.MaxLineLength, max_length: 120},
        {Credo.Check.Design.AliasUsage, excluded_namespaces: ~w[ AMQP Mix ]}
      ]
    }
  ]
}
