defmodule SaveIt.DownloadContext do
  @moduledoc false

  @enforce_keys [:chat_id, :progress_message_id, :original_url]
  defstruct [
    :chat_id,
    :chat,
    :progress_message_id,
    :original_url,
    :download_url,
    :purge_url,
    :cache_url
  ]
end
