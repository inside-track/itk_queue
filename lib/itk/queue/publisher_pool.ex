defmodule ITKQueue.PublisherPool do
  @moduledoc """
  Supervises the pool of channels for publishing
  """
  use Supervisor

  @pool_name :amqp_pub_pool

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg)
  end

  @spec init(term) :: no_return
  def init(_arg) do
    pool_opts = [
      name: {:local, @pool_name},
      worker_module: ITKQueue.PubChannel,
      size: pool_size(),
      max_overflow: max_overflow()
    ]

    children = [
      :poolboy.child_spec(@pool_name, pool_opts)
    ]

    supervise(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Provides a new channel from the pool.

  Example:
    ITKQueue.PublisherPool.with_channel(fn(channel) ->
      # ... do something with the channel
    end)
  """
  def with_channel(action) do
    :poolboy.transaction(@pool_name, fn pid ->
      channel = GenServer.call(pid, :channel)
      action.(channel)
    end)
  end

  @doc """
  Retrieves a connection from the pool.

  You are responsible for returning this connection to the pool when you
  are done with it.

  Example:
    {ref, connection} = ITKQueue.PublisherPool.checkout
    # ... do something with the connection
    ITKQueue.PublisherPool.checkin(ref)
  """
  def checkout do
    if Application.get_env(:itk_queue, :env) == :test && !running_library_tests?() do
      {self(), %AMQP.Channel{}}
    else
      pid = :poolboy.checkout(@pool_name)
      channel = GenServer.call(pid, :channel)
      {pid, channel}
    end
  end

  @doc """
  Return a connection to the pool.
  """
  def checkin(pid) do
    unless Application.get_env(:itk_queue, :env) == :test && !running_library_tests?() do
      :poolboy.checkin(@pool_name, pid)
    end
  end

  defp running_library_tests? do
    Application.get_env(:itk_queue, :running_library_tests, false)
  end

  defp pool_size do
    Application.get_env(:itk_queue, :pub_pool_size, 20)
  end

  def max_overflow do
    Application.get_env(:itk_queue, :max_overflow, pool_size() * 3)
  end
end
