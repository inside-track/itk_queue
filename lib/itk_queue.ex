defmodule ItkQueue do
  use Application

  def start(_type, _args) do
    ITK.Queue.start_link
  end
end
