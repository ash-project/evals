defmodule Evals.Formatter do
  @moduledoc """
  Handles formatting of evaluation results into human-readable reports.
  """

  @doc """
  Formats evaluation results into a report string.

  Takes raw evaluation results and formats them into a report with summaries
  and detailed breakdowns by category and test.

  ## Parameters

  - `results` - A map of evaluation results where keys are tuples of
    `{model_name, category, name, usage_rules}` and values are scores
  - `opts` - The validated options struct from `Evals.Options`
  - `report_opts` - A keyword list of report formatting options

  ## Options

  * `:title` - Custom title for the report (default: "EVALUATION REPORT")
  * `:format` - Format type, either :summary or :full (default: :full)

  ## Returns

  A formatted report string.

  ## Examples

      iex> results = %{{"model1", "cat1", "test1", false} => 0.8}
      iex> opts = %Evals.Options{iterations: 1, usage_rules: false}
      iex> Evals.Formatter.format_report(results, opts, title: "My Report", format: :summary)
      ...> |> String.contains?("My Report")
      true
  """
  @spec format_report(map(), Evals.Options.t(), keyword()) :: String.t()
  def format_report(results, opts, report_opts \\ []) do
    lines = []

    lines = lines ++ ["\n" <> String.duplicate("=", 80)]
    title = Keyword.get(report_opts, :title, "EVALUATION REPORT")
    lines = lines ++ [title]
    lines = lines ++ ["Iterations: #{opts.iterations}"]
    lines = lines ++ [String.duplicate("=", 80)]

    # Overall summary
    lines = lines ++ ["\nOVERALL SUMMARY:"]
    lines = lines ++ [String.duplicate("-", 40)]

    model_summary_lines = format_model_summary(results, opts)
    lines = lines ++ model_summary_lines

    format = Keyword.get(report_opts, :format, :full)

    lines =
      case format do
        :summary ->
          lines ++ ["\n" <> String.duplicate("=", 80)]

        :full ->
          detailed_lines = format_detailed_results(results, opts)
          lines ++ detailed_lines ++ ["\n" <> String.duplicate("=", 80)]
      end

    Enum.join(lines, "\n")
  end

  @spec format_model_summary(map(), Evals.Options.t()) :: [String.t()]
  defp format_model_summary(results, opts) do
    if opts.usage_rules == :compare do
      format_usage_rules_comparison(results)
    else
      format_simple_model_averages(results)
    end
  end

  @spec format_usage_rules_comparison(map()) :: [String.t()]
  defp format_usage_rules_comparison(results) do
    # Break down by usage rules when comparing
    results_by_model_and_rules =
      results
      |> Enum.group_by(fn {{model_name, _, _, usage_rules}, _} ->
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

    with_rules_lines =
      ["", "With usage rules:"] ++
        Enum.map(with_rules_averages, fn {model_name, avg_score} ->
          "  #{String.pad_trailing(model_name, 18)} | #{Float.round(avg_score * 100, 1)}%"
        end)

    without_rules_lines =
      ["", "Without usage rules:"] ++
        Enum.map(without_rules_averages, fn {model_name, avg_score} ->
          "  #{String.pad_trailing(model_name, 18)} | #{Float.round(avg_score * 100, 1)}%"
        end)

    with_rules_lines ++ without_rules_lines
  end

  @spec format_simple_model_averages(map()) :: [String.t()]
  defp format_simple_model_averages(results) do
    # Group results by model for better organization
    results_by_model =
      results
      |> Enum.group_by(fn {{model_name, _, _, _}, _} -> model_name end)

    model_averages =
      Enum.map(results_by_model, fn {model_name, model_results} ->
        avg_score = calculate_average_score(model_results)
        {model_name, avg_score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    Enum.map(model_averages, fn {model_name, avg_score} ->
      "#{String.pad_trailing(model_name, 20)} | #{Float.round(avg_score * 100, 1)}%"
    end)
  end

  @spec format_detailed_results(map(), Evals.Options.t()) :: [String.t()]
  defp format_detailed_results(results, opts) do
    lines = ["\nDETAILED RESULTS:"]
    lines = lines ++ [String.duplicate("-", 80)]

    categories =
      results
      |> Enum.map(fn {{_, category, _, _}, _} -> category end)
      |> Enum.uniq()
      |> Enum.sort()

    category_lines =
      Enum.flat_map(categories, fn category ->
        format_category_results(results, category, opts)
      end)

    lines ++ category_lines
  end

  @spec format_category_results(map(), String.t(), Evals.Options.t()) :: [String.t()]
  defp format_category_results(results, category, opts) do
    category_results =
      results
      |> Enum.filter(fn {{_, cat, _, _}, _} -> cat == category end)
      |> Enum.group_by(fn {{_, _, name, usage_rules}, _} -> {name, usage_rules} end)

    test_lines =
      Enum.flat_map(category_results, fn {{name, usage_rules}, test_results} ->
        format_test_results(name, usage_rules, test_results, opts)
      end)

    ["\n#{String.upcase(category)}:"] ++ test_lines
  end

  @spec format_test_results(String.t(), boolean(), list(), Evals.Options.t()) :: [String.t()]
  defp format_test_results(name, usage_rules, test_results, opts) do
    usage_suffix = if usage_rules, do: " (with usage rules)", else: " (no usage rules)"

    test_header =
      if opts.usage_rules == :compare do
        "  #{name}#{usage_suffix}:"
      else
        "  #{name}:"
      end

    result_lines =
      test_results
      |> Enum.sort_by(fn {{model_name, _, _, _}, _} -> model_name end)
      |> Enum.map(fn {{model_name, _, _, _}, score} ->
        percentage = Float.round(score * 100, 1)
        "    #{String.pad_trailing(model_name, 20)} | #{percentage}%"
      end)

    [test_header] ++ result_lines
  end

  @spec calculate_average_score(list()) :: float()
  defp calculate_average_score(model_results) do
    model_results
    |> Enum.map(fn {_, score} -> score end)
    |> then(fn scores -> Enum.sum(scores) / Enum.count(scores) end)
  end
end
