defmodule ITKQueue.Consumer.Test do
  use ExUnit.Case

  alias ITKQueue.Consumer

  test "can pick up messages after reconnect" do
    pid = self()

    ITKQueue.subscribe("my-test-queue-1", "test.queue1", fn _message -> send(pid, :ok) end)
    ITKQueue.publish("test.queue1", %{test: "first message"})
    assert_receive :ok, 5_000

    # kill the connection used for consumer
    consumer_pid = GenServer.whereis({:global, "my-test-queue-1"})
    {:ok, conn} = GenServer.call(consumer_pid, :connection)
    Process.exit(conn.pid, :kill)

    ITKQueue.publish("test.queue1", %{test: "second message"})
    refute_receive :ok, 100
    assert_receive :ok, 5_000
  end
end
