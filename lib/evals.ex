defmodule Evals do
  @moduledoc """
  The core evaluation engine for the Elixir LLM Evals framework.

  This module is responsible for:
  - Discovering and parsing evaluation files (`.yml`).
  - Preparing and executing evaluation jobs in parallel against multiple LLMs.
  - Sandboxing the execution of model-generated code.
  - Grading the results based on the eval's criteria.
  - Aggregating results for reporting.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  defmodule Options do
    @moduledoc """
    Defines and validates the options for an evaluation run.
    """
    use Spark.Options.Validator,
      schema: [
        system_prompt: [
          type: :string,
          doc: "Override the system prompt to use for the evaluation."
        ],
        debug: [
          type: :boolean,
          default: false,
          doc: "Enable debug mode for the evaluation."
        ],
        usage_rules: [
          type: {:one_of, [true, false, :compare]},
          default: false,
          doc:
            "Specify how to evaluate usage rules. `true` to evaluate all rules, `false` to skip all rules, `:compare` to compare the two."
        ],
        only: [
          type: :string,
          doc: "Only evaluate the specified file path/pattern."
        ],
        iterations: [
          type: :integer,
          default: 1,
          doc: "The number of iterations to run the evaluation. The average score is used."
        ]
      ]
  end

  @doc """
  Runs a full evaluation and returns a formatted report.

  This is the main entry point for running an evaluation suite. It orchestrates
  the evaluation of models and then formats the results into a human-readable string.

  ## Parameters
  - `models`: A keyword list or map of model names to `LangChain.ChatModels` instances.
  - `opts`: A keyword list of options. See `Evals.Options` for evaluation options
    and `Evals.Formatter` for report options like `:title` and `:format`.

  ## Returns
  A tuple `{results, report_text}` where:
  - `results`: A map containing the raw aggregated scores.
  - `report_text`: A formatted string report.
  """
  @spec report(models :: keyword() | map(), opts :: keyword()) :: {map(), String.t()}
  def report(models, opts \\ []) do
    {report_opts, eval_opts} = Keyword.split(opts, [:title, :format])
    opts = %Options{} = Options.validate!(eval_opts)
    results = evaluate(models, eval_opts)
    report_text = Evals.Formatter.format_report(results, opts, report_opts)
    {results, report_text}
  end

  @doc """
  Runs the evaluation logic and returns the raw results.

  ## Parameters
  - `models`: A keyword list or map of model names to `LangChain.ChatModels` instances.
  - `opts`: A keyword list of options. See `Evals.Options` for available options.

  ## Returns
  A map where keys are tuples of `{model_name, category, name, usage_rules}` and
  values are the average scores across all iterations.
  """
  @spec evaluate(models :: keyword() | map(), opts :: keyword()) :: map()
  def evaluate(models, opts \\ []) do
    tmp_dir = Path.join("tmp", to_string(System.unique_integer([:positive])))
    File.mkdir_p!(tmp_dir)

    try do
      opts = %Options{} = Options.validate!(opts)

      evals(opts)
      |> set_usage_rules(opts)
      |> Stream.flat_map(fn eval ->
        Enum.map(models, fn {name, model} ->
          eval
          |> Map.put(:model, model)
          |> Map.put(:model_name, to_string(name))
        end)
      end)
      |> Stream.flat_map(fn eval ->
        Stream.duplicate(eval, opts.iterations)
      end)
      |> Task.async_stream(
        &run_single_eval(&1, tmp_dir, opts),
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok, result}, acc ->
        key = {result.model_name, result.category, result.name, result.usage_rules}
        Map.update(acc, key, [result.grade], &[result.grade | &1])
      end)
      |> Map.new(fn {key, value} -> {key, Enum.sum(value) / Enum.count(value)} end)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  # --- Private Helper Functions ---

  @spec run_single_eval(eval :: map(), tmp_dir :: String.t(), opts :: struct()) :: map()
  defp run_single_eval(eval, tmp_dir, opts) do
    messages = messages(eval, tmp_dir, opts)
    result = result(eval, messages)
    {grade, error, graded_on} = grade(eval, result, tmp_dir)

    if eval[:debug] || opts.debug do
      IO.puts("""
      === DEBUG ===
      model_name: #{eval.model_name}, category: #{eval.category}, name: #{eval.name}, usage_rules: #{eval.usage_rules}
      -------------
      Messages:
      #{Enum.map_join(messages, "\n", &format_message/1)}
      -------------
      Result:

      #{Enum.map_join(String.split(result, "\n"), "\n", &"  #{&1}")}
      -------------
      Graded on:

      #{Enum.map_join(String.split(graded_on, "\n"), "\n", &"  #{&1}")}
      #{if error, do: error}
      =============
      """)
    end

    %{
      model_name: eval.model_name,
      category: eval.category,
      name: eval.name,
      usage_rules: eval.usage_rules,
      grade: grade
    }
  end

  @spec grade(eval :: map(), result :: String.t(), tmp_dir :: String.t()) ::
          {0 | 1, String.t() | nil, String.t()}
  defp grade(%{type: :write_code_and_assert, eval: %{assert: assert}} = eval, result, tmp_dir) do
    {code, assigns} =
      if assert[:wrap_in_module] == true do
        mod = "Generated#{System.unique_integer([:positive])}"
        {"defmodule #{mod} do\n#{result}\nend", %{module_name: mod}}
      else
        {result, %{}}
      end

    {code_with_assertion, graded_on} =
      cond do
        script = assert[:script] ->
          script_text = EEx.eval_string(script, assigns: assigns)

          full_code =
            "#{code}\nrequire ExUnit.Assertions\nimport ExUnit.Assertions\n#{script_text}"

          {full_code, script_text}

        assertion = assert[:assertion] ->
          assertion_text = EEx.eval_string(assertion, assigns: assigns)

          full_code =
            "#{code}\nrequire ExUnit.Assertions\nExUnit.Assertions.assert #{assertion_text}"

          {full_code, assertion_text}

        true ->
          raise "Eval assert must contain either an 'assertion' or a 'script' key."
      end

    case write_and_eval(eval, tmp_dir, code_with_assertion) do
      {_result, 0} -> {1, nil, graded_on}
      {result, _} -> {0, result, graded_on}
    end
  end

  @spec from_yml(map()) :: map()
  defp from_yml(data) do
    data
    |> remap_key("id", :id)
    |> remap_key("description", :description)
    |> remap_key("difficulty", :difficulty, &String.to_atom/1)
    |> remap_key("tags", :tags)
    |> remap_key("type", :type, &String.to_atom/1)
    |> remap_key("code", :code)
    |> remap_key("debug", :debug)
    |> remap_key(
      "install",
      :install,
      &Enum.map(&1, fn install ->
        install
        |> remap_key("package", :package)
        |> remap_key("version", :version)
      end)
    )
    |> remap_key(
      "messages",
      :messages,
      &Enum.map(&1, fn message ->
        message
        |> remap_key("type", :type)
        |> remap_key("text", :text)
      end)
    )
    |> remap_key("eval", :eval, fn eval ->
      eval
      |> remap_key("assert", :assert, fn assert ->
        assert
        |> remap_key("wrap_in_module", :wrap_in_module)
        |> remap_key("assertion", :assertion)
        |> remap_key("script", :script)
      end)
    end)
    |> Map.put(:usage_rules, false)
  end

  # ... existing code ...
  defp set_usage_rules(stream, opts) do
    case opts.usage_rules do
      true ->
        Stream.map(stream, &Map.put(&1, :usage_rules, true))

      false ->
        stream

      :compare ->
        Stream.flat_map(
          stream,
          fn eval ->
            if eval[:install] do
              [Map.put(eval, :usage_rules, true), Map.put(eval, :usage_rules, false)]
            else
              [Map.put(eval, :usage_rules, false)]
            end
          end
        )
    end
  end

  defp system_prompt(%{type: :write_code_and_assert} = eval, tmp_dir, opts) do
    system_prompt =
      opts.system_prompt ||
        "You are an Elixir programmer's assistant."

    system_prompt =
      if eval[:usage_rules] && eval[:install] do
        packages = eval[:install] |> Enum.map(& &1[:package]) |> Enum.join(", ")

        script =
          """
          #{mix_install(eval[:install])}

          Mix.install_project_dir()
          |> Path.join("deps/{#{packages}}/usage-rules.md")
          |> Path.wildcard()
          |> Enum.map_join("\n\n", fn path ->
            name =
              path
              |> Path.split()
              |> Enum.reverse()
              |> Enum.drop(1)
              |> Enum.at(0)

          \"\"\"
          <!-- \#{name}-start -->
          ## \#{name} usage rules
          \#{File.read!(path)}
          <!-- \#{name}-end -->
          \"\"\"
          end)
          |> then(fn rules ->
            "<!-- usage-rules start -->\n" <> rules <> "\n<!-- usage-rules end -->"
          end)
          |> IO.puts()
          """

        {usage_rules, 0} =
          System.cmd("elixir", ["-e", script],
            env: %{"MIX_QUIET" => "true"},
            stderr_to_stdout: true
          )

        usage_rules =
          usage_rules
          |> String.split("<!-- usage-rules start")
          |> Enum.drop(1)
          |> Enum.join("<!-- usage-rules start")

        """
        #{system_prompt}
        #{usage_rules}
        """
      else
        system_prompt
      end

    system_prompt =
      if eval[:code] do
        {output, exit_code} = write_and_eval(eval, tmp_dir, eval[:code])

        diagnostics = clean_diagnostics(output)

        if exit_code == 0 && String.trim(output) == "" do
          """
          #{system_prompt}

          <code>
          #{eval[:code]}
          </code>
          """
        else
          """
          #{system_prompt}

          <code>
          #{eval[:code]}
          </code>
          <diagnostics>
          #{diagnostics}
          </diagnostics>
          """
        end
      else
        system_prompt
      end

    system_prompt <>
      "\nRespond with only the exact source code requested."
  end

  defp clean_diagnostics(output) do
    # Remove unused variable warnings with a regex pattern
    # This matches the multi-line warning format for unused variables
    output
    |> String.replace(
      ~r/warning: variable "[^"]*" is unused \(if the variable is not meant to be used, prefix it with an underscore\)\n\s*│\n\s*\d+\s*│[^\n]*\n\s*│[^\n]*\n\s*│\n\s*└─[^\n]*\n?/m,
      ""
    )
  end

  defp write_and_eval(eval, tmp_dir, code) do
    path = Path.join(tmp_dir, "#{System.unique_integer([:positive])}.ex")

    code =
      if install = eval[:install] do
        """
        #{mix_install(install)}

        #{code}
        """
      else
        code
      end

    File.write!(path, code)

    System.cmd("elixir", [Path.expand(path)],
      stderr_to_stdout: true,
      env: %{"MIX_QUIET" => "true"}
    )
  end

  defp mix_install(install) do
    """
    Mix.install([
      #{Enum.map_join(install, "\n", &"{:#{&1[:package]}, \"#{&1[:version]}\"}")}
      ],
      consolidate_protocols: false
    )
    """
  end

  defp result(%{model: model, type: :write_code_and_assert} = eval, messages, retries_left \\ 10) do
    {:ok, %{last_message: %{content: content}}} =
      %{llm: model}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)
      |> LLMChain.run(mode: :until_success)

    # Handle both string content and ContentPart list formats
    content_text =
      case content do
        # New format: list of ContentPart structs
        [%{content: text} | _] when is_binary(text) -> text
        # Legacy format: direct string
        text when is_binary(text) -> text
        # Fallback: convert to string if possible
        other -> to_string(other)
      end

    case content_text do
      "```elixir\n" <> rest ->
        rest |> String.split("\n```") |> List.first()

      content_text ->
        content_text
    end
  rescue
    e ->
      if retries_left == 0 do
        reraise e, __STACKTRACE__
      else
        result(eval, messages, retries_left - 1)
      end
  end

  defp evals(opts) do
    if opts.only do
      Path.wildcard(opts.only)
    else
      Path.wildcard("evals/*/*")
    end
    # Only process regular files, not directories
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(fn file ->
      [_, category | _] = Path.split(file)

      data = YamlElixir.read_from_file!(file)

      data
      |> from_yml()
      |> Map.put(:category, category)
      |> Map.put_new(:name, Path.basename(file, ".yml"))
    end)
  end

  defp messages(eval, tmp_dir, opts) do
    system_prompt = system_prompt(eval, tmp_dir, opts)

    [
      Message.new_system!(system_prompt)
      | Enum.map(eval[:messages], fn message ->
          case message[:type] do
            "user" -> Message.new_user!(message[:text])
            "assistant" -> Message.new_assistant!(message[:text])
          end
        end)
    ]
  end

  defp remap_key(map, key, new_key, mapper \\ & &1) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        map
        |> Map.put(new_key, mapper.(value))
        |> Map.delete(key)

      :error ->
        map
    end
  end

  defp format_message(%LangChain.Message{role: role, content: content}) do
    # Handle both string content and ContentPart list formats
    content_text =
      case content do
        # New format: list of ContentPart structs
        [%{content: text} | _] when is_binary(text) -> text
        # Legacy format: direct string
        text when is_binary(text) -> text
        # Fallback: convert to string if possible
        other -> inspect(other)
      end

    """
    #{role}:
    #{content_text |> String.split("\n") |> Enum.map(&"  #{&1}") |> Enum.join("\n")}
    """
  end
end
