defmodule SaveIt.CobaltClient do
  require Logger

  use Tesla

  plug(Tesla.Middleware.BaseUrl, "https://api.cobalt.tools")

  plug(Tesla.Middleware.Headers, [
    {"Accept", "application/json"},
    {"Content-Type", "application/json"}
  ])

  plug(Tesla.Middleware.JSON)

  @doc """

  ## Examples
    get_download_url("https://www.instagram.com/p/C9pr7NDPAyd/?igsh=azBiNHJ0ZXd3bTFh") #=>

  """
  # def get_download_url("https://www.instagram.com/" <> _ = text) do
  def get_download_url(text) do
    # https://www.instagram.com/p/C9pr7NDPAyd/?igsh=azBiNHJ0ZXd3bTFh => https://www.instagram.com/p/C9pr7NDPAyd/
    url = String.split(text, "?") |> hd()

    case post("api/json", %{url: url}) do
      {:ok, response} ->
        case response.body do
          %{"url" => url} ->
            # memo: ins single video, response.body is %{"url" => url}
            # %{
            #   "status" => "redirect",
            #   "url" => "https://scontent.cdninstagram.com/..."
            # }
            {:ok, url}

          %{"status" => "picker", "picker" => picker_items} ->
            # [%{"url" => url}] = picker_items
            # error:  you attempted to apply a function named :first on [],  If you are using Kernel.apply/3, make sure the module is an atom. If you are using the dot syntax, such as module.function(), make sure the left-hand side of the dot is an atom representing a module
            {:ok, url, Enum.map(picker_items, &Map.get(&1, "url"))}

          %{"status" => "error", "text" => msg} ->
            Logger.warning("response.body is status error, text: #{msg}")
            {:error, msg}

          _ ->
            Logger.warning("response.body: #{inspect(response.body)}")
            {:error, "inner service error"}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # TODO: get_download_urls for multiple urls
  # def get_download_url(url) do
  #   case post("api/json", %{url: url}) do
  #     {:ok, response} ->
  #       # %{
  #       #   "status" => "redirect",
  #       #   "url" => "https://video.twimg.com/amplify_video/1814202798097268736/vid/avc1/720x1192/HAD9zyJn1xoP4oRN.mp4?tag=16"
  #       # }
  #       %{"url" => url} = response.body
  #       url

  #     # TODO send photo to telegram

  #     {:error, error} ->
  #       error
  #   end
  # end
end
