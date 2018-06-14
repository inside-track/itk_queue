defmodule ITKQueueTest do
  use ExUnit.Case

  setup do
    on_exit(fn ->
      ITKQueue.ConnectionPool.with_connection(fn connection ->
        channel = ITKQueue.Channel.open(connection)
        AMQP.Queue.delete(channel, "my-test-queue-1")
        AMQP.Queue.delete(channel, "my-test-queue-2")
        ITKQueue.Channel.close(channel)
      end)
    end)
  end

  test "publishing and subscribing with a function hander" do
    pid = self()

    {:ok, subscription} =
      ITKQueue.subscribe("my-test-queue-1", "test.queue1", fn _message -> send(pid, :ok) end)

    IO.inspect(subscription, label: "-- started subscription")

    ITKQueue.publish("test.queue1", %{test: "me"})
    assert_receive :ok, 5_000

    Process.exit(subscription, :normal)
  end

  test "retrying failed messages" do
    pid = self()

    {:ok, subscription} =
      ITKQueue.subscribe("my-test-queue-2", "test.queue2", fn _message, headers ->
        {_, _, retry_count} =
          Enum.find(headers, {nil, nil, 0}, fn {name, _type, _value} -> name == "retry_count" end)

        if retry_count > 0 do
          send(pid, :ok)
        else
          raise "try again"
        end
      end)

    ITKQueue.publish("test.queue2", %{test: "me"})
    assert_receive :ok, 5_000

    Process.exit(subscription, :normal)
  end

  test "retrying failed messages without an exception" do
    pid = self()

    {:ok, subscription} =
      ITKQueue.subscribe("my-test-queue-2", "test.queue2", fn _message, headers ->
        {_, _, retry_count} =
          Enum.find(headers, {nil, nil, 0}, fn {name, _type, _value} -> name == "retry_count" end)

        if retry_count > 0 do
          send(pid, :ok)
        else
          {:retry, "try again"}
        end
      end)

    ITKQueue.publish("test.queue2", %{test: "me"})
    assert_receive :ok, 5_000

    Process.exit(subscription, :normal)
  end
end
