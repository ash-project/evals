defmodule Evals.Formatter do
  @moduledoc """
  Handles formatting of evaluation results into Markdown reports.
  """

  @doc """
  Formats evaluation results into a Markdown report string.

  Takes raw evaluation results and formats them into a report with summaries
  and detailed breakdowns by category and test.

  ## Parameters

  - `results` - A map of evaluation results where keys are tuples of
    `{model_name, category, name, assertion_name, usage_rules}` and values are scores
  - `opts` - The validated options struct from `Evals.Options`
  - `report_opts` - A keyword list of report formatting options

  ## Options

  * `:title` - Custom title for the report (default: "EVALUATION REPORT")
  * `:format` - Format type, either :summary or :full (default: :full)

  ## Returns

  A formatted Markdown report string.
  """
  @spec format_report(map(), Evals.Options.t(), keyword()) :: String.t()
  def format_report(results, opts, report_opts \\ []) do
    title = Keyword.get(report_opts, :title, "EVALUATION REPORT")
    format = Keyword.get(report_opts, :format, :full)

    sections = [
      "# #{title}",
      "",
      "**Iterations:** #{opts.iterations}",
      "",
      "## Overall Summary",
      "",
      format_overall_summary(results, opts)
    ]

    sections =
      case format do
        :summary ->
          sections

        :full ->
          sections ++
            [
              "",
              "## Category Summaries",
              "",
              format_category_summaries(results, opts),
              "",
              "## Detailed Results",
              "",
              format_detailed_results(results, opts)
            ]
      end

    Enum.join(sections, "\n")
  end

  @spec format_overall_summary(map(), Evals.Options.t()) :: String.t()
  defp format_overall_summary(results, opts) do
    if opts.usage_rules == :compare do
      format_usage_rules_comparison_table(results)
    else
      format_simple_model_table(results)
    end
  end

  @spec format_usage_rules_comparison_table(map()) :: String.t()
  defp format_usage_rules_comparison_table(results) do
    results_by_model_and_rules =
      results
      |> Enum.group_by(fn {{model_name, _, _, _, usage_rules}, _} ->
        {model_name, usage_rules}
      end)

    with_rules_averages =
      results_by_model_and_rules
      |> Enum.filter(fn {{_, usage_rules}, _} -> usage_rules end)
      |> Enum.map(fn {{model_name, _}, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    without_rules_averages =
      results_by_model_and_rules
      |> Enum.filter(fn {{_, usage_rules}, _} -> not usage_rules end)
      |> Enum.map(fn {{model_name, _}, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    with_rules_table = format_score_table(with_rules_averages)
    without_rules_table = format_score_table(without_rules_averages)

    """
    ### With Usage Rules

    #{with_rules_table}

    ### Without Usage Rules

    #{without_rules_table}
    """
  end

  @spec format_simple_model_table(map()) :: String.t()
  defp format_simple_model_table(results) do
    results_by_model =
      results
      |> Enum.group_by(fn {{model_name, _, _, _, _}, _} -> model_name end)

    model_averages =
      Enum.map(results_by_model, fn {model_name, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    format_score_table(model_averages)
  end

  @spec format_score_table([{String.t(), float()}]) :: String.t()
  defp format_score_table(model_scores) do
    header = "| Model | Score |"
    separator = "|-------|-------|"

    rows =
      Enum.map(model_scores, fn {model_name, avg_score} ->
        percentage = Float.round(avg_score * 100, 1)
        "| #{model_name} | #{percentage}% |"
      end)

    Enum.join([header, separator | rows], "\n")
  end

  @spec format_category_summaries(map(), Evals.Options.t()) :: String.t()
  defp format_category_summaries(results, opts) do
    categories =
      results
      |> Enum.map(fn {{_, category, _, _, _}, _} -> category end)
      |> Enum.uniq()
      |> Enum.sort()

    category_sections =
      Enum.map(categories, fn category ->
        format_category_summary(results, category, opts)
      end)

    Enum.join(category_sections, "\n\n")
  end

  @spec format_category_summary(map(), String.t(), Evals.Options.t()) :: String.t()
  defp format_category_summary(results, category, opts) do
    category_results =
      results
      |> Enum.filter(fn {{_, cat, _, _, _}, _} -> cat == category end)

    category_title = "### #{String.upcase(category)}"

    summary_content =
      if opts.usage_rules == :compare do
        format_category_usage_rules_comparison(category_results)
      else
        format_simple_category_averages(category_results)
      end

    "#{category_title}\n\n#{summary_content}"
  end

  @spec format_category_usage_rules_comparison(list()) :: String.t()
  defp format_category_usage_rules_comparison(category_results) do
    results_by_model_and_rules =
      category_results
      |> Enum.group_by(fn {{model_name, _, _, _, usage_rules}, _} ->
        {model_name, usage_rules}
      end)

    with_rules_averages =
      results_by_model_and_rules
      |> Enum.filter(fn {{_, usage_rules}, _} -> usage_rules end)
      |> Enum.map(fn {{model_name, _}, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    without_rules_averages =
      results_by_model_and_rules
      |> Enum.filter(fn {{_, usage_rules}, _} -> not usage_rules end)
      |> Enum.map(fn {{model_name, _}, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    with_rules_table = format_score_table(with_rules_averages)
    without_rules_table = format_score_table(without_rules_averages)

    """
    **With Usage Rules:**

    #{with_rules_table}

    **Without Usage Rules:**

    #{without_rules_table}
    """
  end

  @spec format_simple_category_averages(list()) :: String.t()
  defp format_simple_category_averages(category_results) do
    results_by_model =
      category_results
      |> Enum.group_by(fn {{model_name, _, _, _, _}, _} -> model_name end)

    model_averages =
      Enum.map(results_by_model, fn {model_name, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    format_score_table(model_averages)
  end

  @spec format_detailed_results(map(), Evals.Options.t()) :: String.t()
  defp format_detailed_results(results, opts) do
    categories =
      results
      |> Enum.map(fn {{_, category, _, _, _}, _} -> category end)
      |> Enum.uniq()
      |> Enum.sort()

    category_sections =
      Enum.map(categories, fn category ->
        format_detailed_category_results(results, category, opts)
      end)

    Enum.join(category_sections, "\n\n")
  end

  @spec format_detailed_category_results(map(), String.t(), Evals.Options.t()) :: String.t()
  defp format_detailed_category_results(results, category, opts) do
    category_results =
      results
      |> Enum.filter(fn {{_, cat, _, _, _}, _} -> cat == category end)
      |> Enum.group_by(fn {{_, _, name, assertion_name, usage_rules}, _} ->
        {name, assertion_name, usage_rules}
      end)

    category_title = "### #{String.upcase(category)}"

    test_sections =
      category_results
      |> Enum.sort_by(fn {{name, assertion_name, _}, _} -> {name, assertion_name} end)
      |> Enum.map(fn {{name, assertion_name, usage_rules}, test_results} ->
        format_test_results_table(name, assertion_name, usage_rules, test_results, opts)
      end)

    "#{category_title}\n\n#{Enum.join(test_sections, "\n\n")}"
  end

  @spec format_test_results_table(String.t(), String.t(), boolean(), list(), Evals.Options.t()) ::
          String.t()
  defp format_test_results_table(name, assertion_name, usage_rules, test_results, opts) do
    usage_suffix = if usage_rules, do: " (with usage rules)", else: " (no usage rules)"
    assertion_suffix = if assertion_name != "default", do: " - #{assertion_name}", else: ""

    test_title =
      if opts.usage_rules == :compare do
        "**#{name}#{assertion_suffix}#{usage_suffix}**"
      else
        "**#{name}#{assertion_suffix}**"
      end

    model_scores =
      test_results
      |> Enum.sort_by(fn {{model_name, _, _, _, _}, _} -> model_name end)
      |> Enum.map(fn {{model_name, _, _, _, _}, score} ->
        percentage = Float.round(score * 100, 1)
        {model_name, percentage}
      end)

    header = "| Model | Score |"
    separator = "|-------|-------|"

    rows =
      Enum.map(model_scores, fn {model_name, percentage} ->
        "| #{model_name} | #{percentage}% |"
      end)

    table = Enum.join([header, separator | rows], "\n")

    "#{test_title}\n\n#{table}"
  end

  @spec calculate_average_score(list()) :: float()
  defp calculate_average_score(model_results) do
    model_results
    |> Enum.map(fn {_, score} -> score end)
    |> then(fn scores -> Enum.sum(scores) / Enum.count(scores) end)
  end
end
