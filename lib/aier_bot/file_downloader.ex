defmodule AierBot.FileDownloader do
  use Tesla

  def download(url, file_path) do
    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        File.write("./downloads/#{file_path}", body)
        IO.puts("File downloaded successfully.")

      {:ok, %Tesla.Env{status: status}} ->
        IO.puts("Failed to download file. Status: #{status}")

      {:error, reason} ->
        IO.puts("Failed to download file. Reason: #{inspect(reason)}")
    end
  end
end
