defmodule ITKQueue.Workers do
  @moduledoc false

  use GenServer

  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  @doc false
  def init(:ok) do
    Process.send_after(self(), :start_workers, 5000)
    {:ok, %{}}
  end

  def handle_info(:start_workers, state) do
    Enum.each :application.loaded_applications(), fn {app, _, _} ->
      {:ok, modules} = :application.get_key(app, :modules)
      Enum.each modules, fn mod ->
        case mod.module_info(:attributes)[:workers] do
          nil -> nil
          _workers -> mod.start_workers()
        end
      end
    end

    {:noreply, state}
  end
end
