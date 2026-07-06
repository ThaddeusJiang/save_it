defmodule SaveIt.Telegram do
  @moduledoc false

  require Logger

  alias SaveIt.Job

  @rate_limit_max_retries 1

  def send_message(chat_id, text, opts \\ []) do
    chat_id
    |> ExGram.send_message(text)
    |> handle_feedback_result(chat_id, opts)
  end

  def update_message(chat_id, message_id, texts) when is_list(texts) do
    update_message(chat_id, message_id, Enum.join(texts, "\n"))
  end

  def update_message(chat_id, message_id, text) do
    text
    |> ExGram.edit_message_text(chat_id: chat_id, message_id: message_id)
    |> handle_feedback_result(chat_id, [])
  end

  def delete_message(chat_id, message_id) do
    ExGram.delete_message(chat_id, message_id)
  end

  def handle_progress_rate_limit(chat, source_message, retry_after, retry_attempt, retry_fun)
      when is_function(retry_fun, 1) do
    if retry_attempt < @rate_limit_max_retries do
      schedule_progress_retry(chat, source_message, retry_after, retry_attempt + 1, retry_fun)
    else
      schedule_notice(chat.id, retry_after, rate_limit_final_message())
    end

    :error
  end

  defp handle_feedback_result({:error, %ExGram.Error{code: 429} = error}, chat_id, opts) do
    retry_after = retry_after(error)

    Logger.warning(
      "Telegram request rate limited chat_id=#{chat_id} " <>
        "retry_after=#{format_log_value(retry_after)}"
    )

    case Keyword.get(opts, :on_rate_limit, :notify) do
      :return ->
        {:error, {:telegram_rate_limited, retry_after}}

      _other ->
        schedule_notice(chat_id, retry_after)
        {:error, :telegram_rate_limited}
    end
  end

  defp handle_feedback_result(result, _chat_id, _opts), do: result

  defp schedule_notice(chat_id, retry_after) do
    schedule_notice(chat_id, retry_after, rate_limit_message(retry_after))
  end

  defp schedule_notice(chat_id, retry_after, message) do
    Job.run_after(rate_limit_delay_ms(retry_after), fn ->
      send_rate_limit_notice(chat_id, message)
    end)
  end

  defp schedule_progress_retry(chat, source_message, retry_after, retry_attempt, retry_fun) do
    delay_ms = rate_limit_delay_ms(retry_after)
    retry_at = retry_at(retry_after)
    notice = rate_limit_retry_message(retry_after, retry_at)

    Job.run_after(delay_ms, fn ->
      send_rate_limit_notice(chat.id, notice)

      retry_attempt
      |> retry_fun.()
      |> maybe_delete_source_message_after_retry(chat, source_message)
    end)
  end

  defp send_rate_limit_notice(chat_id, message) do
    case ExGram.send_message(chat_id, message) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Telegram rate limit notice failed chat_id=#{chat_id} " <>
            "reason=#{format_log_value(reason)}"
        )
    end
  end

  defp maybe_delete_source_message_after_retry(:ok, chat, source_message) do
    case message_id(source_message) do
      message_id when is_integer(message_id) -> delete_message(chat.id, message_id)
      _ -> :ok
    end
  end

  defp maybe_delete_source_message_after_retry(_result, _chat, _source_message), do: :ok

  defp rate_limit_delay_ms(retry_after) do
    case Application.fetch_env(:save_it, :telegram_rate_limit_delay_ms) do
      {:ok, delay_ms} when is_integer(delay_ms) and delay_ms >= 0 -> delay_ms
      _ -> retry_after_delay_ms(retry_after)
    end
  end

  defp retry_after_delay_ms(retry_after) do
    if is_integer(retry_after) and retry_after >= 0, do: retry_after * 1000, else: 0
  end

  defp rate_limit_message(nil) do
    "Telegram is rate limiting me. Please retry later."
  end

  defp rate_limit_message(retry_after) do
    "Telegram is rate limiting me. Please retry after #{retry_after} seconds."
  end

  defp rate_limit_retry_message(nil, retry_at) do
    "Telegram is rate limiting me. Next automatic retry is scheduled for " <>
      "#{format_retry_at(retry_at)}. I will only retry automatically once."
  end

  defp rate_limit_retry_message(retry_after, retry_at) do
    "Telegram is rate limiting me. Next automatic retry is scheduled for " <>
      "#{format_retry_at(retry_at)} (in #{retry_after} seconds). " <>
      "I will only retry automatically once."
  end

  defp rate_limit_final_message do
    "Telegram is still rate limiting me. I will not retry automatically again. Please try again later."
  end

  defp retry_at(retry_after) when is_integer(retry_after) and retry_after >= 0 do
    DateTime.utc_now()
    |> DateTime.add(retry_after, :second)
  end

  defp retry_at(_retry_after), do: DateTime.utc_now()

  defp format_retry_at(%DateTime{} = retry_at) do
    Calendar.strftime(retry_at, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp retry_after(%ExGram.Error{metadata: metadata}) when is_map(metadata) do
    metadata
    |> map_get(:parameters)
    |> map_get(:retry_after)
    |> normalize_retry_after()
  end

  defp retry_after(_error), do: nil

  defp normalize_retry_after(value) when is_integer(value) and value >= 0, do: value

  defp normalize_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds
      _ -> nil
    end
  end

  defp normalize_retry_after(_value), do: nil

  defp message_id(message) when is_map(message) do
    map_get(message, :message_id)
  end

  defp message_id(_message), do: nil

  defp map_get(nil, _key), do: nil

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp format_log_value(nil), do: "nil"
  defp format_log_value(value) when is_binary(value), do: inspect(value)
  defp format_log_value(value), do: inspect(value)
end
