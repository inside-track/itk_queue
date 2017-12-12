defmodule ITKQueue.ConnectionPool do
  @moduledoc """
  Manages a pool of connections to AMQP.

  When a connection is needed call `with_connection/1` and pass it the function that needs the connection.
  The function will be executed with a connection checked out from the pool. After the function completes the
  connection will be checked back into the pool.
  """
  use Supervisor

  alias ITKQueue.Connection

  @pool_name :amqp_pool

  @doc false
  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @doc false
  def init(:ok) do
    pool_opts = [
      name: {:local, @pool_name},
      worker_module: Connection,
      size: pool_size(),
      # max_overflow is always zero because if a subscription is made on a channel using an overflow connection
      # that connection will be closed eventually and that will break the subscription
      max_overflow: 0
    ]

    children = [
      :poolboy.child_spec(@pool_name, pool_opts, amqp_url: amqp_url())
    ]

    supervise(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Provides a connection from the connection pool to perform an action.

  This connection will automatically be returned to the pool when the
  action is complete.

  Example:
    ITKQueue.ConnectionPool.with_connection(fn(connection) ->
      # ... do something with the connection
    end)
  """
  def with_connection(action) do
    :poolboy.transaction(@pool_name, fn pid ->
      connection = GenServer.call(pid, :connection)
      action.(connection)
    end)
  end

  @doc """
  Retrieves a connection from the pool.

  You are responsible for returning this connection to the pool when you
  are done with it.

  Example:
    {ref, connection} = ITKQueue.ConnectionPool.checkout
    # ... do something with the connection
    ITKQueue.ConnectionPool.checkin(ref)
  """
  def checkout do
    if Mix.env() == :test && !running_library_tests?() do
      {self(), %AMQP.Connection{}}
    else
      pid = :poolboy.checkout(@pool_name)
      connection = GenServer.call(pid, :connection)
      {pid, connection}
    end
  end

  @doc """
  Return a connection to the pool.
  """
  def checkin(pid) do
    unless Mix.env() == :test && !running_library_tests?() do
      :poolboy.checkin(@pool_name, pid)
    end
  end

  defp pool_size do
    Application.get_env(:itk_queue, :pool_size, 10)
  end

  defp amqp_url do
    Application.get_env(:itk_queue, :amqp_url, "amqp://localhost:5672")
  end

  defp running_library_tests? do
    Application.get_env(:itk_queue, :running_library_tests, false)
  end
end
