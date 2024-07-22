defmodule AierBot.FileDownloader do
  use Tesla

  def download(url) do
    # https://video.twimg.com/amplify_video/1814202798097268736/vid/avc1/720x1192/HAD9zyJn1xoP4oRN.mp4?tag=16

    IO.puts(url)

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body, headers: headers}} ->
        # TODO: 可以使用异步，并且实时更新 bot 状态
        IO.puts("Downloading file...")

        # [..., {"content-type", "video/mp4"}, ...] = headers
        utc_now_str =
          DateTime.utc_now() |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()

        content_type = headers |> Enum.find(fn {k, _} -> k == "content-type" end) |> elem(1)
        # IO.puts("Content-Type: #{content_type}")
        file_path = (utc_now_str <> "_" <> content_type) |> String.replace("/", ".")

        File.write("./.local/storage/#{file_path}", body)
        IO.puts("File downloaded successfully.")
        {file_path, body}

      {:ok, %Tesla.Env{status: status}} ->
        IO.puts("Failed to download file. Status: #{status}")

      {:error, reason} ->
        IO.puts("Failed to download file. Reason: #{inspect(reason)}")
    end
  end
end
