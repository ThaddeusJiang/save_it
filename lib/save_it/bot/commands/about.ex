defmodule SaveIt.Bot.Commands.About do
  @moduledoc false

  alias SaveIt.Telegram

  def handle(chat) do
    bot_info = bot_info()

    Telegram.send_message(chat.id, """
    SaveIt can download images and videos, just give me a link.

    Chat: #{chat_type(chat)}
    Public: #{public_status(chat)}
    Bot admin: #{bot_admin_status(chat, bot_info)}
    Privacy Mode: #{privacy_mode_status(bot_info)}

    Created by @ThaddeusJiang, powered by Cobalt, Typesense, and Elixir.Access

    Give a star ⭐ if you like it, https://github.com/ThaddeusJiang/save_it
    """)
  end

  defp chat_type(%{type: "private"}), do: "dm"
  defp chat_type(%{type: "group"}), do: "group"
  defp chat_type(%{type: "supergroup"}), do: "group"
  defp chat_type(%{type: "channel"}), do: "channel"
  defp chat_type(%{type: type}) when is_binary(type), do: type
  defp chat_type(_chat), do: "unknown"

  defp public_status(%{username: username}) when is_binary(username) do
    if String.trim(username) == "", do: "no", else: "yes"
  end

  defp public_status(_chat), do: "no"

  defp bot_info, do: ExGram.get_me()

  defp bot_admin_status(%{type: "private"}, _bot_info), do: "n/a"

  defp bot_admin_status(%{id: chat_id}, bot_info) do
    case bot_id(bot_info) do
      nil ->
        "unknown"

      bot_id ->
        case ExGram.get_chat_member(chat_id, bot_id) do
          {:ok, %{status: status}} when status in ["administrator", "creator", "owner"] -> "yes"
          {:ok, %{status: _status}} -> "no"
          {:error, _reason} -> "unknown"
        end
    end
  end

  defp bot_admin_status(_chat, _bot_info), do: "unknown"

  defp bot_id({:ok, bot_info}), do: Map.get(bot_info, :id)
  defp bot_id(_bot_info), do: nil

  defp privacy_mode_status({:ok, bot_info}) do
    case Map.get(bot_info, :can_read_all_group_messages) do
      true -> "disabled"
      false -> "enabled"
      _other -> "unknown"
    end
  end

  defp privacy_mode_status(_bot_info), do: "unknown"
end
