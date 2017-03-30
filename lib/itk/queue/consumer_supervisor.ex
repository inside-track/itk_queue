defmodule ITK.Queue.ConsumerSupervisor do
  use Supervisor

  alias ITK.Queue.{Consumer, Subscription}

  @name :itk_queue_consumer_supervisor

  @doc false
  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: @name)
  end

  @doc false
  def init(:ok) do
    children = [
      worker(Consumer, [], restart: :permanent)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Start a new supervised consumer for a subscription.
  """
  def start_consumer(subscription = %Subscription{}) do
    Supervisor.start_child(@name, [subscription])
  end
end
