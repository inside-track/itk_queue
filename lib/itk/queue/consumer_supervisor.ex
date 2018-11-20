defmodule ITKQueue.ConsumerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ITKQueue.{Consumer, Subscription}

  @doc false
  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc false
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new supervised consumer for a subscription.
  """
  @spec start_consumer(subscription :: Subscription.t()) :: {:ok, pid}
  def start_consumer(subscription = %Subscription{}) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: "#{subscription.queue_name}_consumer",
      start: {Consumer, :start_link, [subscription]},
      restart: :transient
    })
  end
end
