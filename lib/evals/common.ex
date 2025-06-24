defmodule Evals.Common do
  @moduledoc """
  Module for common evaluation sets
  """
  def flagship(opts \\ []) do
    Evals.report(
      [
        "gpt-4.1": LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4.1"}),
        "gpt-4o": LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o"}),
        "claude sonnet 4":
          LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude-sonnet-4-20250514"}),
        "claude sonnet 3.7":
          LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude-3-7-sonnet-latest"})
      ],
      Keyword.put(opts, :title, "Flagship Models")
    )
    |> elem(1)
  end

  def gpt(opts \\ []) do
    Evals.report(
      [
        "gpt-4.1": LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4.1"}),
        "gpt-4o": LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o"})
      ],
      Keyword.put(opts, :title, "GPTs")
    )
    |> elem(1)
  end
end
