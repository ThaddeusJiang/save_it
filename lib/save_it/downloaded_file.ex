defmodule SaveIt.DownloadedFile do
  @moduledoc false

  @enforce_keys [:file_name, :file_content]
  defstruct [:file_name, :file_content, :download_url]
end
