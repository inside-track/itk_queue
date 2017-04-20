defmodule ITKQueue.Publisher do
  @moduledoc false

  use GenServer

  alias ITKQueue.{Connection, Channel}

  @name :itk_queue_publisher
  @exchange Application.get_env(:itk_queue, :amqp_exchange)

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:publish, routing_key, message, headers}, state) do
    connection = Connection.connect()
    channel = Channel.open(connection)
    {:ok, payload} = Poison.encode(message)

    AMQP.Basic.publish(channel, @exchange, routing_key, payload, persistent: true, headers: headers)
    Channel.close(channel)
    {:noreply, state}
  end

  def publish(routing_key, message, headers \\ []) do
    GenServer.cast(@name, {:publish, routing_key, message, headers})
  end
end
