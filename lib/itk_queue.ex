defmodule ItkQueue do
  @moduledoc false

  use Application

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(ITK.Queue.Connection, []),
      worker(ITK.Queue.Publisher, []),
      supervisor(ITK.Queue.ConsumerSupervisor, [])
    ]

    opts = [strategy: :one_for_one, name: ITK.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
