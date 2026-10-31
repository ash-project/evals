defmodule EvalsTest do
  use ExUnit.Case
  import Mock

  alias Evals.Options

  # Helper mock module for testing
  defmodule MockChatModel do
    defstruct []
  end

  describe "Options" do
    test "validates with default options" do
      opts = Options.validate!([])
      assert opts.debug == false
      assert opts.usage_rules == false
      assert opts.iterations == 1
      assert opts.system_prompt == nil
      assert opts.only == nil
    end

    test "validates with custom options" do
      opts =
        Options.validate!(
          debug: true,
          usage_rules: :compare,
          iterations: 5,
          system_prompt: "Custom prompt",
          only: "evals/test/*.yml"
        )

      assert opts.debug == true
      assert opts.usage_rules == :compare
      assert opts.iterations == 5
      assert opts.system_prompt == "Custom prompt"
      assert opts.only == "evals/test/*.yml"
    end

    test "validates usage_rules options" do
      assert Options.validate!(usage_rules: true).usage_rules == true
      assert Options.validate!(usage_rules: false).usage_rules == false
      assert Options.validate!(usage_rules: :compare).usage_rules == :compare
    end
  end

  describe "report/2" do
    test "splits options correctly" do
      # Test the basic option splitting logic without invoking full evaluation
      {report_opts, eval_opts} = Keyword.split([title: "Test", debug: true], [:title, :format])

      assert report_opts == [title: "Test"]
      assert eval_opts == [debug: true]
    end
  end

  describe "evaluate/2" do
    test "validates options before evaluation" do
      models = [test: %MockChatModel{}]

      assert_raise Spark.Options.ValidationError, fn ->
        Evals.evaluate(models, usage_rules: :invalid)
      end
    end

    test "creates temporary directory structure" do
      # This test only validates the basic function signature and file handling
      with_mock File, [:passthrough],
        mkdir_p!: fn path ->
          assert String.starts_with?(path, "tmp/")
          :ok
        end,
        rm_rf!: fn path ->
          assert String.starts_with?(path, "tmp/")
          :ok
        end do
        with_mock Path, [:passthrough], wildcard: fn _pattern -> [] end do
          models = [test: %MockChatModel{}]
          result = Evals.evaluate(models, [])
          assert is_map(result)
        end
      end
    end
  end

  describe "from_yml/1 and grade/3 for match_output" do
    test "parses match_output eval configuration with expected_output" do
      yaml_data = %{
        "type" => "match_output",
        "messages" => [
          %{"type" => "user", "text" => "Write a script that prints 'Hello, World!'."}
        ],
        "eval" => %{
          "expected_output" => "Hello, World!\n"
        }
      }

      parsed = Evals.from_yml(yaml_data)

      assert parsed.type == :match_output
      assert parsed.eval.expected_output == "Hello, World!\n"
    end

    test "grades matching stdout as 1 ignoring leading and trailing whitespace" do
      tmp_dir = Path.join(System.tmp_dir!(), "evals_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      try do
        eval =
          Evals.from_yml(%{
            "type" => "match_output",
            "eval" => %{"expected_output" => "  Hello, World!\n"}
          })

        assert [{"default", 1, nil, "  Hello, World!\n"}] =
                 Evals.grade(eval, ~s|IO.puts("Hello, World!")|, tmp_dir)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "grades mismatched stdout or non-zero exit as 0" do
      tmp_dir = Path.join(System.tmp_dir!(), "evals_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      try do
        eval =
          Evals.from_yml(%{
            "type" => "match_output",
            "eval" => %{"expected_output" => "Hello, World!"}
          })

        assert [{"default", 0, actual, "Hello, World!"}] =
                 Evals.grade(eval, ~s|IO.puts("Wrong output")|, tmp_dir)

        assert String.trim(actual) == "Wrong output"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
