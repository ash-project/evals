defmodule Evals.Common do
  @moduledoc """
  Common evaluation functions for running evaluations against different model providers.

  This module provides convenience functions for running evaluations against
  popular model families like flagship models, GPT models, and Gemini models.

  ## Example

      # Run evaluations against Gemini models
      Evals.Common.gemini()

      # Run with custom options
      Evals.Common.gemini(only: "evals/elixir/**/*.yml")

  """

  @doc """
  Runs evaluations against flagship models from multiple providers.

  Returns evaluation results for GPT-4.1, GPT-4o, Claude Sonnet 4, and Claude Sonnet 3.7.
  """
  @spec flagship(keyword()) :: String.t()
  def flagship(opts \\ []) do
    Evals.report(
      [
        "gpt-4.1": LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4.1"}),
        "claude sonnet 4":
          LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude-sonnet-4-20250514"}),
        "gemini-2.5-pro": LangChain.ChatModels.ChatGoogleAI.new!(%{model: "gemini-2.5-pro"})
      ],
      Keyword.put(opts, :title, "Flagship Models")
    )
    |> elem(1)
  end

  @doc """
  Runs evaluations against Anthropic Claude models.

  Returns evaluation results for Claude Sonnet 4 and Claude Sonnet 3.7.

  ## Example

      # Run against all evaluations
      Evals.Common.anthropic()

      # Run with custom options
      Evals.Common.anthropic(only: "evals/elixir/**/*.yml")

  """
  @spec anthropic(keyword()) :: String.t()
  def anthropic(opts \\ []) do
    Evals.report(
      [
        "claude sonnet 4":
          LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude-sonnet-4-20250514"}),
        "claude sonnet 3.7":
          LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude-3-7-sonnet-latest"})
      ],
      Keyword.put(opts, :title, "Anthropic Models")
    )
    |> elem(1)
  end

  @doc """
  Runs evaluations against OpenAI GPT models.

  Returns evaluation results for GPT-4.1 and GPT-4o.
  """
  @spec gpt(keyword()) :: String.t()
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

  @doc """
  Runs evaluations against Google Gemini models.

  Returns evaluation results for Gemini 2.0 Flash and Gemini 1.5 Pro.

  ## Example

      # Run against all evaluations
      Evals.Common.gemini()

      # Run specific patterns
      Evals.Common.gemini(only: "evals/elixir_core/*.yml")

  """
  @spec gemini(keyword()) :: String.t()
  def gemini(opts \\ []) do
    Evals.report(
      [
        "gemini-2.5-flash": LangChain.ChatModels.ChatGoogleAI.new!(%{model: "gemini-2.5-flash"}),
        "gemini-2.0-flash": LangChain.ChatModels.ChatGoogleAI.new!(%{model: "gemini-2.0-flash"})
      ],
      Keyword.put(opts, :title, "Gemini Models")
    )
    |> elem(1)
  end
end
