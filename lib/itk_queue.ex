defmodule ItkQueue do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(ITK.Queue, [])
    ]

    opts = [strategy: :one_for_one, name: ITK.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
