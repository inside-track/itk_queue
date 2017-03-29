defmodule ITK.QueueTest do
  use ExUnit.Case

  defmodule TestQueueSubscriber do
    def start_link do
      GenServer.start_link(__MODULE__, :ok, [name: :test_subscriber])
    end

    def init(:ok) do
      {:ok, %{}}
    end

    def handle_cast({:message, message}, _state) do
      {:noreply, message}
    end

    def handle_call({:message}, _from, state) do
      {:reply, state, nil}
    end

    def get_message do
      GenServer.call(:test_subscriber, {:message})
    end
  end

  test "publishing and subscribing with a function hander" do
    pid = self()
    ITK.Queue.subscribe("my-test-queue-1", "test.queue1", fn(_) -> send pid, :ok end)
    ITK.Queue.publish("test.queue1", %{test: "me"})
    assert_receive :ok, 5_000
  end

  test "publishing and subscribing with a process handler" do
    {:ok, pid} = TestQueueSubscriber.start_link
    ITK.Queue.subscribe("my-test-queue-2", "test.queue2", pid)
    ITK.Queue.publish("test.queue2", %{test: "me"})
    Process.sleep(1000)
    assert TestQueueSubscriber.get_message() == %{test: "me"}
  end
end
