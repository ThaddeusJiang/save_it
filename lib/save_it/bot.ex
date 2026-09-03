defmodule SaveIt.Bot do
  @moduledoc false

  require Logger

  alias SaveIt.Bot.Commands
  alias SaveIt.Bot.MediaUpload
  alias SaveIt.Bot.TextHelper
  alias SaveIt.Bot.UrlDownload
  alias SaveIt.PhotoService

  @bot :save_it_bot

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  command("start")

  command("search", description: "Search photos")
  command("delete", description: "Delete message")
  command("info", description: "Show media info")

  command("google_drive_login", description: "Connect Google Drive")
  command("google_drive_folder", description: "Set Google Drive folder ID")

  command("about", description: "Know more about this bot")

  middleware(ExGram.Middleware.IgnoreUsername)

  def bot, do: @bot

  def handle({:command, :start, _msg}, context) do
    answer(context, Commands.Start.message())
  end

  def handle({:command, :about, %{chat: chat}}, _context) do
    Commands.About.handle(chat)
  end

  def handle({:command, :google_drive_login, %{chat: chat} = message}, _context) do
    Commands.GoogleDrive.handle_login(chat, Map.get(message, :from))
  end

  def handle({:command, :google_drive_folder, %{chat: chat, text: text}}, _context) do
    Commands.GoogleDrive.handle_folder(chat, text)
  end

  def handle({:command, :search, %{chat: chat, photo: [_ | _] = photos} = message}, _context) do
    Commands.Search.handle_photos(message, chat, photos)
  end

  def handle({:command, :search, %{chat: chat, text: nil}}, _context) do
    Commands.Search.handle_missing_query(chat)
  end

  def handle({:command, :search, %{chat: chat, text: text}}, _context)
      when is_binary(text) do
    Commands.Search.handle_query(chat, text)
  end

  def handle({:command, :info, %{chat: chat, reply_to_message: reply_to_message}}, _context) do
    Commands.Info.handle(chat, reply_to_message)
  end

  def handle({:command, :delete, %{chat: chat, reply_to_message: nil}}, _ctx) do
    Commands.Delete.handle_missing_reply(chat)
  end

  def handle(
        {:command, :delete,
         %{chat: chat, message_id: message_id, from: from, reply_to_message: reply_to_message}},
        _ctx
      ) do
    Commands.Delete.handle(chat, message_id, from, reply_to_message)
  end

  # caption: nil -> find same photos
  # caption: contains /search -> search similar photos; otherwise, find same photos
  def handle({:message, %{chat: chat, photo: [_ | _] = photos} = message}, _ctx) do
    MediaUpload.handle_photo(message, chat, Map.get(message, :caption), photos)
  end

  def handle({:message, %{chat: chat, video: %{file_id: _file_id} = video} = message}, _ctx) do
    MediaUpload.handle_video(message, chat, Map.get(message, :caption), video)
  end

  def handle({:text, text, %{chat: chat, photo: [_ | _] = photos} = message}, _context)
      when is_binary(text) do
    case TextHelper.extract_urls(text) do
      [] -> MediaUpload.handle_photo(message, chat, text, photos)
      urls -> UrlDownload.handle_text_urls(text, message, urls)
    end
  end

  def handle({:text, text, message}, _context) do
    case TextHelper.extract_urls(text) do
      [] -> :ok
      urls -> UrlDownload.handle_text_urls(text, message, urls)
    end
  end

  def handle({:edited_message, %{photo: nil}}, _context) do
    Logger.debug("Ignoring edited message without photo")
    # Edited search commands are ignored for now.
    {:ok, nil}
  end

  def handle({:edited_message, %{chat: chat, caption: caption, photo: photos}}, _context) do
    file_id = photos |> List.last() |> Map.get(:file_id)
    PhotoService.update_photo_caption!(file_id, chat.id, caption)
  end

  def handle({:update, _update}, _context) do
    Logger.debug("Ignoring unsupported update")
    {:ok, nil}
  end

  def handle({:message, _message}, _context) do
    Logger.debug("Ignoring unsupported message")
    {:ok, nil}
  end
end
