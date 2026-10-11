%{
  configs: [
    %{
      name: "default",
      strict: true,
      # Entfernt (2026-10): IoPuts, ExpensiveEmptyStringCheck, MapMixing,
      # NegatedConditionInUnless (Tippfehler neben der korrekten Pluralform)
      # und TailTrailingNewline existierten in der installierten
      # Credo-Version nicht — sie liefen nie ("Ignoring an undefined check"-
      # Rauschen) und wurden aus der Allowlist entfernt. Der strict-Dispatch
      # verpflichtet jede App auf alle verbleibenden Checks; Ausnahmen nur
      # als begründeter --exclude (aktuell: ratsprojekte).
      checks: [
        {Credo.Check.Consistency.TabsOrSpaces, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.SpaceInParentheses, []},
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.ModuleAttributeNames, []},
        {Credo.Check.Readability.PredicateFunctionNames, []},
        {Credo.Check.Readability.TrailingBlankLine, []},
        {Credo.Check.Readability.TrailingWhiteSpace, []},
        {Credo.Check.Readability.VariableNames, []},
        {Credo.Check.Readability.SinglePipe, []},
        {Credo.Check.Refactor.DoubleBooleanNegation, []},
        {Credo.Check.Refactor.CondStatements, []},
        {Credo.Check.Refactor.CyclomaticComplexity, []},
        {Credo.Check.Refactor.FunctionArity, []},
        {Credo.Check.Refactor.LongQuoteBlocks, []},
        {Credo.Check.Refactor.MatchInCondition, []},
        {Credo.Check.Refactor.NegatedConditionsInUnless, []},
        {Credo.Check.Refactor.Nesting, []},
        {Credo.Check.Refactor.PipeChainStart, []},
        {Credo.Check.Refactor.UnlessWithElse, []},
        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.BoolOperationOnSameValues, []},
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.UnsafeToAtom, []},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.UnusedKeywordOperation, []},
        {Credo.Check.Warning.UnusedListOperation, []},
        {Credo.Check.Warning.UnusedStringOperation, []},
        {Credo.Check.Warning.UnusedTupleOperation, []}
      ]
    }
  ]
}
