import Config

config :langchain, :openai_key, System.get_env("OPENAI_API_KEY")
config :langchain, :anthropic_key, System.get_env("ANTHROPIC_API_KEY")
