defmodule ITKQueue.SyslogLogger do
  defstruct queue_name: "", routing_key: ""

  alias ITKQueue.SyslogLogger

  def error(logger = %SyslogLogger{}, message) do
    log(logger, "33", message)
  end

  def error(queue_name, routing_key, message) do
    error(%SyslogLogger{queue_name: queue_name, routing_key: routing_key}, message)
  end

  def info(logger = %ITKQueue.SyslogLogger{}, message) do
    log(logger, "36", message)
  end

  def info(queue_name, routing_key, message) do
    info(%SyslogLogger{queue_name: queue_name, routing_key: routing_key}, message)
  end

  defp log(logger, priority, message) do
    IO.puts ~s(<#{priority}>1 #{timestamp()} #{hostname()} #{name(logger)} - - [queue@0 name="#{logger.queue_name}" routing_key="#{logger.routing_key}"] #{message}")
  end

  defp name(logger) do
    System.get_env("APP_NAME") || logger.queue_name || logger.routing_key
  end

  defp timestamp do
    DateTime.utc_now |> DateTime.to_iso8601
  end

  defp hostname do
    {:ok, hostname} = :inet.gethostname
    hostname
  end
end
