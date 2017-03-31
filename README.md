# ITK Queue

Provides convenience functions for subscribing to queues and publishing messages.

## Installation

The package can be installed by adding `itk_queue` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:itk_queue, "~> 0.2.0"}]
end
```

You should also update your application list to include `:itk_queue`:

```elixir
def application do
  [applications: [:itk_queue]]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile ITK Queue.

## Configuration

The URL and the the exchange that should be used need to be provided as configuration settings

```elixir
config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "development"
```

## Publishing Messages

Message publishing is as simple as providing the routing key and the message to be published. The message should be
something that can be encoded as JSON.

```elixir
ITKQueue.publish("routing.key", %{my: "message"})
```

## Subscribing

Subscribing to queues requires a queue name, the routing key, and a function that will be called when
a message is received. The message will be the body of the message parsed as JSON.

If the handler function raises an exception the message will be moved to a temporary queue and retried after a delay.

```elixir
ITKQueue.subscribe("my-queue", "routing.key", fn(message) -> IO.puts inspect message end)
```

The handler function can take two forms. If you are only interested in the message received use:

```elixir
fn(message) -> ... end
```

If you would also like the headers that were included with the message use:

```elixir
fn(message, headers) -> ... end
```
