defmodule Evals.CommonTest do
  use ExUnit.Case
  doctest Evals.Common

  import Mock

  describe "flagship/1" do
    test "returns formatted report for flagship models" do
      with_mock Evals, [:passthrough],
        report: fn models, opts ->
          assert length(models) == 3
          assert Keyword.get(opts, :title) == "Flagship Models"

          # Check that all expected models are present
          model_names = Keyword.keys(models)
          assert :"gpt-4.1" in model_names
          assert :"claude sonnet 4" in model_names
          assert :"gemini-2.5-flash" in model_names

          {%{}, "Flagship Models Report"}
        end do
        result = Evals.Common.flagship()
        assert result == "Flagship Models Report"
      end
    end

    test "passes through additional options" do
      with_mock Evals, [:passthrough],
        report: fn _models, opts ->
          assert Keyword.get(opts, :title) == "Flagship Models"
          assert Keyword.get(opts, :only) == "test/*.yml"
          {%{}, "Report"}
        end do
        Evals.Common.flagship(only: "test/*.yml")
      end
    end
  end

  describe "gpt/1" do
    test "returns formatted report for GPT models" do
      with_mock Evals, [:passthrough],
        report: fn models, opts ->
          assert length(models) == 2
          assert Keyword.get(opts, :title) == "GPTs"

          model_names = Keyword.keys(models)
          assert :"gpt-4.1" in model_names
          assert :"gpt-4o" in model_names

          {%{}, "GPTs Report"}
        end do
        result = Evals.Common.gpt()
        assert result == "GPTs Report"
      end
    end
  end

  describe "gemini/1" do
    test "returns formatted report for Gemini models" do
      with_mock Evals, [:passthrough],
        report: fn models, opts ->
          assert length(models) == 2
          assert Keyword.get(opts, :title) == "Gemini Models"

          model_names = Keyword.keys(models)
          assert :"gemini-2.5-flash" in model_names
          assert :"gemini-2.0-flash" in model_names

          {%{}, "Gemini Models Report"}
        end do
        result = Evals.Common.gemini()
        assert result == "Gemini Models Report"
      end
    end

    test "supports only option for specific patterns" do
      with_mock Evals, [:passthrough],
        report: fn _models, opts ->
          assert Keyword.get(opts, :only) == "evals/elixir_core/*.yml"
          {%{}, "Report"}
        end do
        Evals.Common.gemini(only: "evals/elixir_core/*.yml")
      end
    end
  end
end
