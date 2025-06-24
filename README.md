# Evals

A evaluation tool for testing and comparing AI language models on various coding tasks. This allows you to run structured evaluations, compare model performance with and without usage rules, and generate detailed reports.

## Features

- **Multiple Model Support**: Evaluate and compare different language models side-by-side
- **Usage Rules Integration**: Test how well models follow specific package usage rules and guidelines
- **Code Generation & Validation**: Evaluate models on code writing tasks with automated assertion testing
- **Flexible Evaluation Options**: Control iterations, debug output, and evaluation scope
- **Rich Reporting**: Generate summary or detailed reports with performance breakdowns
- **YAML-Based Test Definitions**: Define evaluations in simple YAML files organized by category

## Roadmap

- For `write_code_and_assert` type, more complex setup tasks where the LLM only needs to generate a subset of a response, not all the code.
- Different types of evals, like `response_contains`,  `response_doesnt_contain`, and also `llm_judge` where you ask a separate judge LLM if a certain property is attained by the output.
- The ability to experiment with different system prompts, i.e does "you are an expert Elixir developer" matter?
- The ability to benchmark fully agentic flows like multi-turn working with hex docs search, plan files, custom context etc.

## Report

We only have a few evals here, but eventually this will be expensive for me to
operate, so its not running in CI etc. I will run it when I feel like its worth
running again, when the are more evals etc. Others are encouraged to run this
locally with their own keys if they want to throw a few coins in the machine to
help out.

See the [reports folder](reports/) for more.

For example:

[reports/flagship](reports/flagship.md?plain=1)

## Quick Start

```elixir
# Define your models
models = [
  {"gpt-4", %LangChain.ChatModels.ChatOpenAI{model: "gpt-4"}},
  {"claude-3-sonnet", %LangChain.ChatModels.ChatAnthropic{model: "claude-3-sonnet-20240229"}}
]

# Run evaluations and get a report
{results, report} = Evals.report(models,
  usage_rules: :compare,
  title: "Model Comparison",
  format: "summary"
)

IO.puts(report)
```

## Common Model Comparisons

The `Evals.Common` module provides convenient functions for testing common model combinations:

### Flagship Models

Compare the latest flagship models from OpenAI and Anthropic:

```elixir
# Quick flagship comparison
report = Evals.Common.flagship(usage_rules: :compare, format: "summary")
IO.puts(report)

# Full detailed report
report = Evals.Common.flagship(usage_rules: :compare, format: :full)
IO.puts(report)
```

This compares:
- GPT-4.1
- GPT-4o
- Claude Sonnet 4
- Claude Sonnet 3.7

### GPT Models Only

Compare different GPT model variants:

```elixir
report = Evals.Common.gpt(usage_rules: :compare)
IO.puts(report)
```

This compares:
- GPT-4.1
- GPT-4o

All `Evals.Common` functions accept the same options as `Evals.report/2` and return the formatted report string directly.

## Contributing Evaluations

We welcome contributions of new evaluation cases! Here's how to add your own:

### Creating a New Evaluation

1. **Choose a category** or create a new one in the `evals/` directory
2. **Create a YAML file** with a descriptive name (e.g., `async_genserver.yml`)
3. **Follow the evaluation format** shown below

### Evaluation Guidelines

- **Be specific**: Test one clear concept or skill per evaluation
- **Include context**: Provide enough background in the user message
- **Write clear assertions**: Make sure your test validates the intended behavior
- **Test edge cases**: Consider boundary conditions and common mistakes
- **Add realistic scenarios**: Use examples that mirror real-world usage

### Example Contribution

```yaml
# evals/genserver/async_operations.yml
type: write_code_and_assert
messages:
  - type: user
    text: |
      Write a function called `add` that adds two numbers. Return just the function, not wrapped in a module
eval:
  assert:
    # wrap the answer in a module
    wrap_in_module: true
    assertion: "<%= @module_name %>.add(2, 3) == 5"
```

### Testing Your Evaluation

Before submitting, test your evaluation locally:

```elixir
# Test only your new evaluation
{results, report} = Evals.report(models, only: "evals/your_category/your_eval.yml")
IO.puts(report)
```

## Evaluation Structure

Evaluations are organized in the `evals/` directory by category:

```
evals/
├── basic_elixir/
│   ├── pattern_matching.yml
│   └── list_operations.yml
├── ash_framework/
│   ├── resource_definition.yml
│   └── changeset_usage.yml
└── phoenix/
    ├── controller_actions.yml
    └── live_view_basics.yml
```

Each YAML file defines a test case with:
- **Type**: Currently supports `write_code_and_assert`
- **Messages**: Conversation history leading to the code generation request
- **Code**: Optional existing code context
- **Install**: Package dependencies to install
- **Eval**: Assertion criteria for validating the generated code

### Example Evaluation File

```yaml
type: write_code_and_assert
install:
  - package: ash
    version: "~> 3.0"
messages:
  - type: user
    text: "Create a basic Ash resource for a User with name and email fields"
eval:
  assert:
    wrap_in_module: true
    assertion: |
      Code.ensure_loaded(<%= assigns.module_name %>)
      function_exported?(<%= assigns.module_name %>, :__resource__, 0)
```

## API Reference

### Core Functions

#### `Evals.evaluate(models, opts \\ [])`

Runs evaluations and returns raw results.

**Options:**
- `:iterations` - Number of runs per test (default: 1). Higher iterations will cause much longer evaluation times due to rate limits
- `:usage_rules` - `:compare`, `true`, or `false` (default: `false`)
- `:only` - Limit to specific file pattern
- `:debug` - Enable debug output
- `:system_prompt` - Override system prompt

#### `Evals.report(models, opts \\ [])`

Runs evaluations and returns formatted report.

**Additional Report Options:**
- `:title` - Custom report title
- `:format` - `:summary` or `:full` (default: `:full`)

### Usage Rules

When `:usage_rules` is enabled, the framework automatically:
1. Installs specified packages via `Mix.install`
2. Locates `usage-rules.md` files in package dependencies
3. Includes these rules in the system prompt
4. Compares model performance with and without rules (when `:compare`)

### Example Results

```elixir
results = %{
  {"gpt-4", "ash_framework", "resource_definition", true} => 0.85,
  {"gpt-4", "ash_framework", "resource_definition", false} => 0.72,
  {"claude-3-sonnet", "ash_framework", "resource_definition", true} => 0.78,
  {"claude-3-sonnet", "ash_framework", "resource_definition", false} => 0.65
}
```

## Report Formats

### Summary Format
Shows only model averages, optionally broken down by usage rules:

```
================================================================================
Model Performance Comparison
Iterations: 1
================================================================================

OVERALL SUMMARY:
----------------------------------------

With usage rules:
  gpt-4              | 85.2%
  claude-3-sonnet    | 82.1%

Without usage rules:
  gpt-4              | 72.4%
  claude-3-sonnet    | 69.8%
================================================================================
```

### Full Format
Includes detailed breakdown by category and individual tests.

## Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd evals
   ```

2. **Install dependencies:**
   ```bash
   mix deps.get
   ```

3. **Set up your API keys:**
   ```bash
   export OPENAI_API_KEY="your-openai-key"
   export ANTHROPIC_API_KEY="your-anthropic-key"
   ```

4. **Run evaluations:**
   ```bash
   iex -S mix
   ```

   Then in the IEx console:
   ```elixir
   models = [
     {"gpt-4", %LangChain.ChatModels.ChatOpenAI{model: "gpt-4"}},
     {"claude-3-sonnet", %LangChain.ChatModels.ChatAnthropic{model: "claude-3-sonnet-20240229"}}
   ]

   {results, report} = Evals.report(models, usage_rules: :compare)
   IO.puts(report)
   ```
