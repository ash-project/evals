defmodule Evals.FormatterTest do
  use ExUnit.Case
  doctest Evals.Formatter

  alias Evals.{Formatter, Options}

  describe "format_report/3" do
    setup do
      opts = %Options{iterations: 1, usage_rules: false}

      results = %{
        {"model1", "category1", "test1", false} => 0.8,
        {"model1", "category1", "test2", false} => 0.6,
        {"model2", "category1", "test1", false} => 0.9,
        {"model2", "category2", "test3", false} => 0.7
      }

      %{opts: opts, results: results}
    end

    test "formats basic report with default options", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts)

      assert String.contains?(report, "EVALUATION REPORT")
      assert String.contains?(report, "OVERALL SUMMARY")
      assert String.contains?(report, "DETAILED RESULTS")
      assert String.contains?(report, "Iterations: 1")
      assert String.contains?(report, "CATEGORY1:")
      assert String.contains?(report, "CATEGORY2:")
    end

    test "formats report with custom title", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts, title: "Custom Test Report")

      assert String.contains?(report, "Custom Test Report")
      refute String.contains?(report, "EVALUATION REPORT")
    end

    test "formats summary report when format is :summary", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts, format: :summary)

      assert String.contains?(report, "OVERALL SUMMARY")
      refute String.contains?(report, "DETAILED RESULTS")
    end

    test "includes model averages in summary", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts)

      # Both models should appear with their calculated averages
      assert String.contains?(report, "model1")
      assert String.contains?(report, "model2")
      # model1 average: (0.8 + 0.6) / 2 = 0.7 = 70%
      assert String.contains?(report, "70.0%")
      # model2 average: (0.9 + 0.7) / 2 = 0.8 = 80%
      assert String.contains?(report, "80.0%")
    end

    test "formats detailed results with test breakdowns", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts, format: :full)

      assert String.contains?(report, "test1:")
      assert String.contains?(report, "test2:")
      assert String.contains?(report, "test3:")

      # Check individual test scores are present
      # model1, test1
      assert String.contains?(report, "80.0%")
      # model1, test2
      assert String.contains?(report, "60.0%")
      # model2, test1
      assert String.contains?(report, "90.0%")
      # model2, test3
      assert String.contains?(report, "70.0%")
    end
  end

  describe "format_report/3 with usage rules comparison" do
    setup do
      opts = %Options{iterations: 1, usage_rules: :compare}

      results = %{
        {"model1", "category1", "test1", true} => 0.8,
        {"model1", "category1", "test1", false} => 0.6,
        {"model2", "category1", "test1", true} => 0.9,
        {"model2", "category1", "test1", false} => 0.7
      }

      %{opts: opts, results: results}
    end

    test "formats usage rules comparison in summary", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts)

      assert String.contains?(report, "With usage rules:")
      assert String.contains?(report, "Without usage rules:")

      # Check that models appear in both sections
      lines = String.split(report, "\n")
      with_rules_section = Enum.find_index(lines, &String.contains?(&1, "With usage rules:"))

      without_rules_section =
        Enum.find_index(lines, &String.contains?(&1, "Without usage rules:"))

      assert with_rules_section < without_rules_section
    end

    test "shows usage rules suffix in detailed results", %{opts: opts, results: results} do
      report = Formatter.format_report(results, opts, format: :full)

      assert String.contains?(report, "(with usage rules)")
      assert String.contains?(report, "(no usage rules)")
    end
  end

  describe "edge cases" do
    test "handles empty results" do
      opts = %Options{iterations: 1, usage_rules: false}
      report = Formatter.format_report(%{}, opts)

      assert String.contains?(report, "EVALUATION REPORT")
      assert String.contains?(report, "OVERALL SUMMARY")
    end

    test "handles single model result" do
      opts = %Options{iterations: 1, usage_rules: false}
      results = %{{"solo-model", "test", "single", false} => 1.0}

      report = Formatter.format_report(results, opts)

      assert String.contains?(report, "solo-model")
      assert String.contains?(report, "100.0%")
    end
  end
end
