require Logger

defmodule ITKQueue.Connection do
  @moduledoc """
  Manages a connection to AMQP.
  """

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    Logger.info("Establishing AMQP connection")
    Process.flag(:trap_exit, true)
    connection = connect(Keyword.get(opts, :amqp_url))
    {:ok, connection}
  end

  @doc false
  def handle_call(:connection, _from, connection) do
    {:reply, connection, connection}
  end

  @doc false
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  defp connect(url) do
    url
    |> AMQP.Connection.open()
    |> handle_connection_result(url)
  end

  defp handle_connection_result({:ok, connection}, _url) do
    Process.link(connection.pid)
    connection
  end

  defp handle_connection_result({:error, _}, url) do
    Logger.info("AMQP connection failed, retrying")
    Process.sleep(1000)
    connect(url)
  end

  def terminate(reason, connection) do
    Logger.info("Terminating AMQP connection (#{reason})")

    if Process.alive?(connection.pid) do
      Logger.info("Closing AMQP connection")
      Process.unlink(connection.pid)
      AMQP.Connection.close(connection)
    end

    :normal
  end
end
