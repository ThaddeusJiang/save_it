defmodule SaveIt.FilenameGeneratorTest do
  use ExUnit.Case, async: true

  alias SaveIt.FilenameGenerator

  test "generates uuidv7 filename with the original URL extension" do
    file_name = FilenameGenerator.random("https://example.com/downloads/video.mp4?token=abc")

    assert_uuidv7_filename(file_name, ".mp4")
  end

  test "generates a fresh uuidv7 filename for each call" do
    first = FilenameGenerator.random("https://example.com/photo.jpg")
    second = FilenameGenerator.random("https://example.com/photo.jpg")

    assert_uuidv7_filename(first, ".jpg")
    assert_uuidv7_filename(second, ".jpg")
    assert first != second
  end

  test "uses the fallback extension when the original has no extension" do
    file_name =
      FilenameGenerator.random("https://example.com/download", fallback_extension: ".jpeg")

    assert_uuidv7_filename(file_name, ".jpeg")
  end

  defp assert_uuidv7_filename(file_name, extension) do
    assert file_name =~
             Regex.compile!(
               "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}#{Regex.escape(extension)}$"
             )
  end
end
