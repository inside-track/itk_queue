# ITK Queue

Provides convenience functions for subscribing to queues and publishing messages.

## Installation

The package can be installed by adding `itk_queue` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:itk_queue, "~> 0.2.1"}]
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

The URL and the the exchange that should be used need to be provided as configuration settings. You can also
indicate whether or not you want the parsed messages to use atom keys or strings. The default is to use atoms.

An optional error handler can also be provided. This should be a function that accepts the queue name,
routing key, payload, and exception.

```elixir
defmodule MyErrorHandler do
  def handle(queue_name, routing_key, payload, e) do
    # do something
  end
end
```

The default error handler logs the error using the default `Logger`.

```elixir
config :itk_queue,
  amqp_url: "amqp://localhost:5672",
  amqp_exchange: "development",
  use_atom_keys: false,
  error_handler: &MyErrorHandler.handle/4,
  fallback_endpoint: false
```

### Fallback Configuration

If publishing a message fails the routing key and data can be published to an optional fallback endpoint. This can configured by setting `fallback_endpoint` to the URL the data should be sent to. If the endpoint is set to `false` then it will not be used. If the endpoint requires basic authentication the `fallback_username` and `fallback_password` options can be set. The data will be sent as form-encoded data in the keys `routing_key` and `content`.

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
