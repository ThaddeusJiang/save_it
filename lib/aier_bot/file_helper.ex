defmodule AierBot.FileHelper do
  use Tesla

  # youtube video download url: "https://olly.imput.net/api/stream?id=WpsLJCeQ24MBD_xM_3uwu&exp=1721625834931&sig=4UvjCvFD57jU7yrLdwmzRmfsPgPb8KhFIE1DwmnOj14&sec=C1Hty_eEXvswFhzdrDfDZ4cmkSUDgex1aV6mzDSK0dc&iv=ozku3rLJzeV_rVRSzWVlFw"
  def download("https://olly.imput.net/api/stream" <> _ = url) do
    IO.inspect(url, label: "Download URL")

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        file_name = gen_desc_filename() <> ".mp4"
        {:ok, file_name, body}

      {:ok, %Tesla.Env{status: status}} ->
        IO.puts("Failed to download file. Status: #{status}")
        {:error, "Failed to download file"}

      {:error, reason} ->
        IO.puts("Failed to download file. Reason: #{inspect(reason)}")
        {:error, "Failed to download file"}
    end
  end

  def download(url) do
    IO.inspect(url, label: "Download URL")

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body, headers: headers}} ->
        ext =
          headers
          |> Enum.find(fn {k, _} -> k == "content-type" end)
          |> elem(1)
          |> String.split("/")
          |> List.last()

        file_name = gen_desc_filename() <> "." <> ext
        {:ok, file_name, body}

      {:ok, %Tesla.Env{status: status}} ->
        IO.puts("Failed to download file. Status: #{status}")
        {:error, "Failed to download file"}

      {:error, reason} ->
        IO.puts("Failed to download file. Reason: #{inspect(reason)}")
        {:error, "Failed to download file"}
    end
  end

  def write_into_file(chat_id, file_name, file_content) do
    dir = Path.join(["./.local/storage", Integer.to_string(chat_id)])

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(Path.join([dir, file_name]), file_content) do
          :ok ->
            IO.puts("File written successfully.")

          {:error, reason} ->
            IO.puts("Failed to write file: #{reason}")
        end

      {:error, reason} ->
        IO.puts("Failed to create directory: #{reason}")
    end
  end

  # version 2: 2124-01-01 00:00:00 UTC is 4624022400
  # version 1: 10^16 - current_time, since JS max_safe_integer is 2^53 - 1 = 9007199254740991
  defp gen_desc_filename(datetime \\ DateTime.utc_now()) do
    last = ~U[2124-01-01 00:00:00Z] |> DateTime.to_unix()
    current = datetime |> DateTime.to_unix()

    (last - current)
    |> Integer.to_string()
    |> String.pad_leading(10, "0")
  end
end
