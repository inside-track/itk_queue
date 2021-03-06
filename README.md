# ITK Queue

Provides convenience functions for subscribing to queues and publishing messages.

## Installation

The package can be installed by adding `itk_queue` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:itk_queue, "~> 0.11.0"}]
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
  fallback_endpoint: false,
  max_retries: 10
```

### Fallback Configuration

If publishing a message fails the routing key and data can be published to an optional fallback endpoint. This can configured by setting `fallback_endpoint` to the URL the data should be sent to. If the endpoint is set to `false` then it will not be used. If the endpoint requires basic authentication the `fallback_username` and `fallback_password` options can be set. The data will be sent as form-encoded data in the keys `routing_key` and `content`.

### Rejecting Messages

When a message needs to be retried, the number of retries can be limited by setting `max_retries`. After the specified number of retries has been exceeded the message will be rejected. To retry indefinitely either leave out the `max_retries` configuration or set it to `-1`.

## Publishing Messages

Message publishing is as simple as providing the routing key and the message to be published. The message should be
something that can be encoded as JSON.

```elixir
ITKQueue.publish("routing.key", %{my: "message"})
```

## Subscribing

Subscribing to queues requires a queue name, the routing key, and a function that will be called when
a message is received. The message will be the body of the message parsed as JSON.

If the handler function raises an exception or returns `{:retry, some_message}`, the message will be moved to a temporary queue and retried after a delay.

If the handler function returns `{:reject, some_message}`, the message will be rejected without being retried.

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

## Automatic Worker Registration

In order to have your queue workers automatically started for you you should `use ITKQueue.Worker` and call the `subscribe/3` macro it provides.

```elixir
defmodule MyWorker do
  use ITKQueue.Worker

  subscribe("my.queue.name", "my.routing.key", &process/1)

  def process(message) do
    # do something with the message
  end
end
```

## Publishing itk-queue Package

- Register with an account on https://hex.pm, ping @islam.hamdi/@maruika.wei for granting ownership of the package.
- Go to the correct path under `itk_queue/` locally, run `mix hex.publish` and follow the steps (requires hex.pm account creds).
- Once your package has been published to hex repos, update the dependent services (e.g: itk-stuendets/...) to use the new version instead.
