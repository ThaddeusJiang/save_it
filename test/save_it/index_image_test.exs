defmodule SaveIt.IndexImageTest do
  use ExUnit.Case, async: false

  alias SaveIt.IndexImage

  setup do
    previous = Application.get_env(:save_it, :index_image_converter)

    Application.put_env(:save_it, :index_image_converter, __MODULE__.Converter)

    on_exit(fn ->
      restore_env(previous)
    end)

    :ok
  end

  test "keeps jpeg bytes unchanged" do
    jpeg = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>

    assert {:ok, ^jpeg} = IndexImage.jpeg_bytes("preview.jpg", jpeg)
  end

  test "converts webp bytes before Typesense indexing" do
    assert {:ok, "converted-jpeg"} = IndexImage.jpeg_bytes("preview.webp", "webp-bytes")
  end

  test "exposes a placeholder JPEG for required Typesense image fields" do
    jpeg = IndexImage.fallback_jpeg()

    assert is_binary(jpeg)
    assert jpeg != ""
  end

  defp restore_env(nil), do: Application.delete_env(:save_it, :index_image_converter)
  defp restore_env(value), do: Application.put_env(:save_it, :index_image_converter, value)

  defmodule Converter do
    def convert_file_content("webp-bytes", "preview.webp"), do: {:ok, "converted-jpeg"}
  end
end
