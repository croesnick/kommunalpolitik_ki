%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: [
        {Credo.Check.Consistency.TabsOrSpaces, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.SpaceInParentheses, []},
        {Credo.Check.Consistency.TailTrailingNewline, []},
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
        {Credo.Check.Refactor.NegatedConditionInUnless, []},
        {Credo.Check.Refactor.NegatedConditionsInUnless, []},
        {Credo.Check.Refactor.Nesting, []},
        {Credo.Check.Refactor.PipeChainStart, []},
        {Credo.Check.Refactor.UnlessWithElse, []},
        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.IoPuts, []},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.BoolOperationOnSameValues, []},
        {Credo.Check.Warning.ExpensiveEmptyStringCheck, []},
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.MapMixing, []},
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
