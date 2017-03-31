defmodule ITKQueue.Connection do
  @moduledoc """
  Manages connections to AMQP.
  """

  use GenServer

  @url Application.get_env(:itk_queue, :amqp_url)
  @name :itk_queue_connection

  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: @name])
  end

  @doc false
  def init(:ok) do
    {:ok, %{}}
  end

  @doc false
  def handle_call(:connection, _from, state) do
    connection = state[:connection] || do_connect()
    {:reply, connection, state |> Map.put(:connection, connection)}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state |> Map.delete(:connection)}
  end

  @doc """
  Retrieves a connection to AMQP. Either returns the existing connection or establishes a new one.

  Returns an `AMQP.Connection`.
  """
  def connect do
    GenServer.call(@name, :connection)
  end

  defp do_connect do
    case AMQP.Connection.open(@url) do
      {:ok, connection} ->
        Process.monitor(connection.pid)
        connection
      {:error, _} ->
        Process.sleep(1000)
        connect()
    end
  end
end
