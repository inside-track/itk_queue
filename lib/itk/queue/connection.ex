defmodule ITKQueue.Connection do
  @moduledoc """
  Manages connections to AMQP.
  """

  use GenServer

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
  @spec connect() :: AMQP.Connection.t
  def connect do
    GenServer.call(@name, :connection)
  end

  @spec do_connect() :: AMQP.Connection.t
  defp do_connect do
    case AMQP.Connection.open(amqp_url()) do
      {:ok, connection} ->
        Process.monitor(connection.pid)
        connection
      {:error, _} ->
        Process.sleep(1000)
        connect()
    end
  end

  defp amqp_url do
    Application.get_env(:itk_queue, :amqp_url)
  end
end
