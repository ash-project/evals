defmodule Mix.Tasks.Evals.Report do
  @moduledoc """
  Run evaluation reports for different model groups.

  This task allows you to run evaluations against predefined model groups
  (flagship, gpt, gemini) with various options.

  ## Usage

      mix evals.report <report_type> [options]

  ## Report Types

    * `flagship` - Run evaluations against flagship models (GPT-4.1, GPT-4o, Claude Sonnet 4, Claude Sonnet 3.7)
    * `gpt` - Run evaluations against GPT models (GPT-4.1, GPT-4o)  
    * `gemini` - Run evaluations against Gemini models (Gemini 2.5 Flash, Gemini 2.0 Flash)
    * `anthropic` - Run evaluations against Anthropic Claude models (Claude Sonnet 4, Claude Sonnet 3.7)

  ## Options

    * `--only` - Only evaluate specific file path/pattern (e.g. "evals/elixir/**/*.yml")
    * `--system-prompt` - Override the system prompt for the evaluation
    * `--debug` - Enable debug mode
    * `--usage-rules` - How to evaluate usage rules: true, false, or compare, defaults to compare
    * `--iterations` - Number of iterations to run (default: 1)
    * `--title` - Custom title for the report
    * `--format` - Report format: summary or full (default: full)
    * `-f, --file` - Write results to a file instead of stdout

  ## Examples

      # Run flagship models evaluation
      mix evals.report flagship

      # Run Gemini models with specific pattern
      mix evals.report gemini --only "evals/elixir_core/*.yml"

      # Run GPT models with debug mode and custom iterations
      mix evals.report gpt --debug --iterations 3

      # Run with custom title and compare usage rules
      mix evals.report flagship --title "My Custom Report" --usage-rules compare

      # Write results to a file
      mix evals.report gemini -f report.txt
  """

  use Mix.Task

  @shortdoc "Run evaluation reports for different model groups"

  @switches [
    only: :string,
    system_prompt: :string,
    debug: :boolean,
    usage_rules: :string,
    iterations: :integer,
    title: :string,
    format: :string,
    file: :string
  ]

  @aliases [
    f: :file
  ]

  @impl true
  def run(args) do
    {opts, args} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    case args do
      [report_type] ->
        Mix.Task.run("app.start")
        File.mkdir_p!("reports")
        Mix.shell().info("Generating #{report_type} report.")

        # Convert string usage_rules to appropriate value
        opts = convert_usage_rules(opts)

        # Convert string format to atom
        opts = convert_format(opts)

        report = run_report(report_type, opts)

        filename = Keyword.get(opts, :file) || "reports/#{report_type}.md"

        Mix.shell().info(report)

        File.write!(filename, report)
        Mix.shell().info("Report written to #{filename}")

      _ ->
        Mix.raise("""
        Invalid arguments. Expected: mix evals.report <report_type> [options]

        Report types: flagship, gpt, gemini, anthropic

        Run `mix help evals.report` for more information.
        """)
    end
  end

  defp convert_usage_rules(opts) do
    case Keyword.get(opts, :usage_rules) do
      "true" ->
        Keyword.put(opts, :usage_rules, true)

      "false" ->
        Keyword.put(opts, :usage_rules, false)

      "compare" ->
        Keyword.put(opts, :usage_rules, :compare)

      nil ->
        Keyword.put(opts, :usage_rules, :compare)

      other ->
        Mix.raise("Invalid --usage-rules value: #{other}. Expected: true, false, or compare")
    end
  end

  defp convert_format(opts) do
    case Keyword.get(opts, :format) do
      "summary" -> Keyword.put(opts, :format, :summary)
      "full" -> Keyword.put(opts, :format, :full)
      nil -> opts
      other -> Mix.raise("Invalid --format value: #{other}. Expected: summary or full")
    end
  end

  defp run_report("flagship", opts), do: Evals.Common.flagship(opts)
  defp run_report("gpt", opts), do: Evals.Common.gpt(opts)
  defp run_report("gemini", opts), do: Evals.Common.gemini(opts)
  defp run_report("anthropic", opts), do: Evals.Common.anthropic(opts)

  defp run_report(type, _opts) do
    Mix.raise("Unknown report type: #{type}. Expected: flagship, gpt, gemini, or anthropic")
  end
end

