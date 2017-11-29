defmodule ITKQueue.Connection do
  @moduledoc """
  Manages connections to AMQP.
  """

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{url: Keyword.get(opts, :amqp_url)}}
  end

  @doc false
  def handle_call(:connection, _from, state = %{url: url}) do
    connection = state[:connection] || do_connect(url)
    {:reply, connection, state |> Map.put(:connection, connection)}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state |> Map.delete(:connection)}
  end

  @spec do_connect(url :: String.t()) :: AMQP.Connection.t()
  defp do_connect(url) do
    case AMQP.Connection.open(url) do
      {:ok, connection} ->
        Process.monitor(connection.pid)
        connection

      {:error, _} ->
        Process.sleep(1000)
        do_connect(url)
    end
  end

  def terminate(_reason, %{connection: connection}) do
    AMQP.Connection.close(connection)
    :normal
  end

  def terminate(_reason, _state) do
    :normal
  end
end
