defmodule Evals do
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  defmodule Options do
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
          default: 5,
          doc: "The number of iterations to run the evaluation. The average score is used."
        ]
      ]
  end

  def report(models, opts \\ []) do
    {report_opts, eval_opts} = Keyword.split(opts, [:title, :format])
    opts = %Options{} = Options.validate!(eval_opts)
    results = evaluate(models, eval_opts)
    report_text = Evals.Formatter.format_report(results, opts, report_opts)
    {results, report_text}
  end

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
        fn eval ->
          messages = messages(eval, tmp_dir, opts)
          result = result(eval, messages)
          {grade, error, graded_on} = grade(eval, result, tmp_dir)

          if eval[:debug] || opts.debug do
            IO.puts("""
            === DEBUG ===
            model_name: #{eval.model_name}
            category: #{eval.category}
            name: #{eval.name}
            usage_rules: #{eval.usage_rules}
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

          Map.take(eval, [:model_name, :category, :name, :usage_rules])
          |> Map.put(:grade, grade)
        end,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok,
                              %{
                                model_name: model_name,
                                name: name,
                                category: category,
                                usage_rules: usage_rules,
                                grade: grade
                              }},
                             acc ->
        Map.update(acc, {model_name, category, name, usage_rules}, [grade], &[grade | &1])
      end)
      |> Map.new(fn {key, value} -> {key, Enum.sum(value) / Enum.count(value)} end)
    after
      File.rm_rf!(tmp_dir)
    end
  end

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

  defp grade(%{type: :write_code_and_assert, eval: %{assert: assert}} = eval, result, tmp_dir) do
    {code, assigns} =
      if assert[:gets_module] == true do
        mod =
          "Generated#{System.unique_integer([:positive])}"

        {"defmodule #{mod} do\n#{result}\nend", %{module_name: mod}}
      else
        {result, %{}}
      end

    assertion =
      EEx.eval_string(assert[:assertion], assigns: assigns)

    code_with_assertion =
      """
      #{code}
      require ExUnit.Assertions
      ExUnit.Assertions.assert #{assertion}
      """

    case write_and_eval(
           eval,
           tmp_dir,
           code_with_assertion
         ) do
      {_result, 0} -> {1, nil, assertion}
      {result, _} -> {0, result, assertion}
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

  defp result(%{model: model, type: :write_code_and_assert}, messages) do
    {:ok, %{last_message: %{content: content}}} =
      %{llm: model}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)
      |> LLMChain.run(mode: :while_needs_response, max_retry_count: 12)

    case content do
      "```elixir\n" <> rest ->
        rest |> String.split("\n```") |> List.first()

      content ->
        content
    end
  end

  defp evals(opts) do
    if opts.only do
      Path.wildcard(opts.only)
    else
      Path.wildcard("evals/*/*")
    end
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

  def from_yml(data) do
    data
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
        |> remap_key("gets_module", :gets_module)
        |> remap_key(
          "assertion",
          :assertion
        )
      end)
    end)
    |> Map.put(:usage_rules, false)
  end

  defp format_message(%LangChain.Message{role: role, content: content}) do
    """
    #{role}:
    #{content |> String.split("\n") |> Enum.map(&"  #{&1}") |> Enum.join("\n")}
    """
  end
end
