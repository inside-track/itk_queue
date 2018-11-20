defmodule ITKQueue.Workers do
  @moduledoc false

  use GenServer

  @doc false
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, [])
  end

  @doc false
  def init(_arg) do
    if start_workers?() do
      Process.send_after(self(), :start_workers, 5000)
    end

    {:ok, %{}}
  end

  def handle_info(:start_workers, state) do
    Enum.each(:application.loaded_applications(), fn {app, _, _} ->
      start_workers_for_application(app)
    end)

    {:noreply, state}
  end

  defp start_workers_for_application(app) do
    {:ok, modules} = :application.get_key(app, :modules)
    Enum.each(modules, &start_workers_for_module/1)
  end

  defp start_workers_for_module(module) do
    case module.module_info(:attributes)[:workers] do
      nil -> nil
      _workers -> module.start_workers()
    end
  end

  defp start_workers? do
    case System.get_env("ITK_QUEUE_START_WORKERS") do
      "true" -> true
      nil -> true
      _ -> false
    end
  end
end
