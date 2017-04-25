defmodule ITKQueue.Fallback do
  @moduledoc false

  @endpoint Application.get_env(:itk_queue, :fallback_endpoint)
  @username Application.get_env(:itk_queue, :fallback_username)
  @password Application.get_env(:itk_queue, :fallback_password)

  def publish(routing_key, message) do
    do_publish(@endpoint, routing_key, message)
  end

  defp do_publish(false, _, _), do: nil

  defp do_publish(endpoint, routing_key, message) do
    {:ok, payload} = Poison.encode(message)
    {:ok, %HTTPoison.Response{status_code: 201}} =
      HTTPoison.post(endpoint, {:form, [routing_key: routing_key, content: payload]}, [{"Content-Type", "application/x-www-form-urlencoded"}], publish_options())
  end

  defp publish_options do
    case [@username, @password] do
      [nil, nil] -> []
      [username, password] -> [hackney: [basic_auth: {username, password}]]
    end
  end
end
