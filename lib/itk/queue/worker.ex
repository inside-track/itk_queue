defmodule ITKQueue.Worker do
  @moduledoc """
  Provides automatic registration of queue workers.

  Example:

  defmodule MyWorker do
    use ITKQueue.Worker

    subscribe("my.queue.name", "my.routing.key", &process/1)

    def process(message) do
      # do something with the message
    end
  end
  """

  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :workers, accumulate: true, persist: true)

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def start_workers do
        Enum.each(@workers, fn(worker_name) -> apply(__MODULE__, worker_name, []) end)
      end
    end
  end

  @doc """
  Call to register a process to handle all messages received on a queue with the given routing key.

  See ITKQueue.subscribe/3 for more information.
  """
  defmacro subscribe(queue_name, routing_key, handler) do
    worker_name = String.to_atom("#{queue_name}-#{routing_key}")

    quote do
      @workers unquote(worker_name)

      def unquote(worker_name)() do
        ITKQueue.subscribe(unquote(queue_name), unquote(routing_key), unquote(handler))
      end
    end
  end
end
