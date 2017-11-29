use Mix.Config

case Mix.env() do
  :dev -> import_config "dev.exs"
  :test -> import_config "test.exs"
end
