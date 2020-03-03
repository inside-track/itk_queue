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

  test "can skip invalid json message" do
    pid = self()
    ITKQueue.subscribe("my-test-queue-2", "test.queue1", fn _message -> send(pid, :ok) end)
    consumer_pid = GenServer.whereis({:global, "my-test-queue-2"})

    # replace channel with this test process, so the basic ack comes to us
    s = :sys.get_state(consumer_pid)
    ch = %AMQP.Channel{s.channel | pid: pid}
    GenServer.call(consumer_pid, {:replace_state, %Consumer{s | channel: ch}})

    # deliver message straight to the consumer
    send(consumer_pid, {:basic_deliver, "{\"key\":\"second message\"", %{delivery_tag: 42}})

    assert_receive {_, _, {:call, {:"basic.ack", _, _}, _, _}}, 5_000
    refute_receive :ok, 100
  end
end
