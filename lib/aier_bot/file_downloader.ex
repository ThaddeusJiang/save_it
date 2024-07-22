defmodule AierBot.FileDownloader do
  use Tesla

  # youtube video download url: "https://olly.imput.net/api/stream?id=WpsLJCeQ24MBD_xM_3uwu&exp=1721625834931&sig=4UvjCvFD57jU7yrLdwmzRmfsPgPb8KhFIE1DwmnOj14&sec=C1Hty_eEXvswFhzdrDfDZ4cmkSUDgex1aV6mzDSK0dc&iv=ozku3rLJzeV_rVRSzWVlFw"
  def download("https://olly.imput.net/api/stream" <> _ = url) do
    IO.inspect(url, label: "Download URL")

    case get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        file_name = gen_desc_filename() <> ".mp4"
        File.write("./.local/storage/#{file_name}", body)
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
        File.write("./.local/storage/#{file_name}", body)
        {:ok, file_name, body}

      {:ok, %Tesla.Env{status: status}} ->
        IO.puts("Failed to download file. Status: #{status}")
        {:error, "Failed to download file"}

      {:error, reason} ->
        IO.puts("Failed to download file. Reason: #{inspect(reason)}")
        {:error, "Failed to download file"}
    end
  end

  @spec gen_desc_filename() :: String.t()
  defp gen_desc_filename() do
    # 10^16 - current_time = 9999999999999999 - current_time = 9999999999999999 - 1630848000000 = 9999999998361159
    max = :math.pow(10, 16) |> round()
    utc_now = DateTime.utc_now() |> DateTime.to_unix()

    (max - utc_now)
    |> Integer.to_string()
    |> String.pad_leading(16, "0")
  end
end
