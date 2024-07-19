defmodule AierBot.CobaltClient do
  alias AierBot.FileDownloader
  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.cobalt.tools")

  plug(Tesla.Middleware.Headers, [
    {"Accept", "application/json"},
    {"Content-Type", "application/json"}
  ])

  plug(Tesla.Middleware.JSON)

  def json(url) do
    case post("api/json", %{url: url}) do
      {:ok, response} ->
        # %{
        #   "status" => "redirect",
        #   "url" => "https://video.twimg.com/amplify_video/1814202798097268736/vid/avc1/720x1192/HAD9zyJn1xoP4oRN.mp4?tag=16"
        # }
        %{"url" => url} = response.body
        file_content = FileDownloader.download(url, "video.mp4")
        file_content

      # TODO send photo to telegram

      {:error, error} ->
        error
    end
  end
end
