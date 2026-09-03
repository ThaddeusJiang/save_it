defmodule SaveIt.Bot.Commands.GoogleDrive do
  @moduledoc false

  require Logger

  alias SaveIt.Bot.TextHelper
  alias SaveIt.FileHelper
  alias SaveIt.GoogleOAuth2DeviceFlow
  alias SaveIt.Telegram

  def handle_login(chat, from) do
    case login_permission(chat, from) do
      :ok ->
        login(chat)

      {:error, :not_admin} ->
        Telegram.send_message(
          chat.id,
          "You are not an administrator, you can't connect Google Drive."
        )

      {:error, :unsupported_chat} ->
        Telegram.send_message(chat.id, "You can't connect Google Drive in this chat.")
    end
  end

  def handle_folder(chat, text) do
    folder_id = TextHelper.normalize_command_text(text)

    if folder_id == "" do
      Telegram.send_message(chat.id, "Please provide a Google Drive folder ID.")
    else
      FileHelper.set_google_drive_folder_id(chat.id, folder_id)
      Telegram.send_message(chat.id, "Google Drive folder ID set successfully.")
    end
  end

  defp login(chat) do
    device_code = FileHelper.get_google_device_code(chat.id)

    if TextHelper.present?(device_code) do
      exchange_device_code(chat, device_code)
    else
      request_device_code(chat)
    end
  end

  defp request_device_code(chat) do
    case GoogleOAuth2DeviceFlow.get_device_code() do
      {:ok, response} ->
        FileHelper.set_google_device_code(chat.id, response["device_code"])

        Telegram.send_message(chat.id, """
        Open the following URL in your browser:
        #{response["verification_url"] || response["verification_uri"]}
        Enter code:
        """)

        Telegram.send_message(chat.id, """
        #{response["user_code"]}
        """)

        Telegram.send_message(chat.id, """
        After approving access, run `/google_drive_login` again.
        """)

      {:error, {:missing_config, key}} ->
        Logger.error("Google Drive login config missing", key: key)
        Telegram.send_message(chat.id, missing_oauth_config_message(key))

      {:error, %{body: %{"error" => "invalid_client"}}} ->
        Logger.error("Google Drive login config invalid")
        Telegram.send_message(chat.id, invalid_oauth_client_message())

      {:error, _error} ->
        Logger.error("Failed to get Google Drive login code")
        Telegram.send_message(chat.id, "Failed to get Google Drive login code.")
    end
  end

  defp exchange_device_code(chat, device_code) do
    case GoogleOAuth2DeviceFlow.exchange_device_code_for_token(device_code) do
      {:ok, %{"access_token" => access_token}} when is_binary(access_token) ->
        FileHelper.set_google_access_token(chat.id, access_token)
        FileHelper.set_google_device_code(chat.id, "")
        Telegram.send_message(chat.id, "Google Drive connected.")

      {:error, %{body: %{"error" => "authorization_pending"}}} ->
        Telegram.send_message(chat.id, """
        Google authorization is not complete yet.

        Approve access in your browser, then run `/google_drive_login` again.
        """)

      {:error, {:missing_config, key}} ->
        Logger.error("Google Drive login config missing", key: key)
        Telegram.send_message(chat.id, missing_oauth_config_message(key))

      {:error, %{body: %{"error" => "invalid_client"}}} ->
        FileHelper.set_google_device_code(chat.id, "")
        Logger.error("Google Drive login config invalid")
        Telegram.send_message(chat.id, invalid_oauth_client_message())

      {:error, %{body: %{"error" => error}}} when error in ["access_denied", "expired_token"] ->
        FileHelper.set_google_device_code(chat.id, "")

        Telegram.send_message(chat.id, """
        Google Drive login code expired or was denied.

        Run `/google_drive_login` to get a new code.
        """)

      {:error, _error} ->
        Logger.error("Failed to connect Google Drive")

        Telegram.send_message(chat.id, """
        Failed to connect Google Drive.

        Please run `/google_drive_login` again.
        """)
    end
  end

  defp missing_oauth_config_message(:google_oauth_client_id) do
    """
    Google Drive login is not configured.

    Ask the bot operator to set GOOGLE_OAUTH_CLIENT_ID, then run `/google_drive_login` again.
    """
  end

  defp missing_oauth_config_message(:google_oauth_client_secret) do
    """
    Google Drive login is not configured.

    Ask the bot operator to set GOOGLE_OAUTH_CLIENT_SECRET, then run `/google_drive_login` again.
    """
  end

  defp invalid_oauth_client_message do
    """
    Google Drive login configuration is invalid.

    Ask the bot operator to verify GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET match a Google OAuth client whose application type is TVs and Limited Input devices.

    After fixing the configuration, run `/google_drive_login` again.
    """
  end

  defp login_permission(%{type: "private"}, _from), do: :ok

  defp login_permission(%{type: type} = chat, from)
       when type == "group" or type == "supergroup" do
    {:ok, members} = ExGram.get_chat_administrators(chat.id)

    cond do
      Map.get(from || %{}, :is_bot) ->
        :ok

      Enum.any?(members, &(&1.user.id == Map.get(from || %{}, :id))) ->
        :ok

      true ->
        {:error, :not_admin}
    end
  end

  defp login_permission(_chat, _from), do: {:error, :unsupported_chat}
end
