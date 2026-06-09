defmodule SaveIt.GoogleDriveDelivery do
  @moduledoc false

  alias SaveIt.DownloadContext
  alias SaveIt.DownloadedFile
  alias SaveIt.GoogleDrive

  def async_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    Task.async(fn -> deliver_downloaded_file(context, file) end)
  end

  def async_downloaded_files(%DownloadContext{} = context, files) when is_list(files) do
    Task.async(fn -> deliver_downloaded_files(context, files) end)
  end

  defp deliver_downloaded_file(%DownloadContext{} = context, %DownloadedFile{} = file) do
    safe_upload_result(fn ->
      GoogleDrive.upload_file_content(context.chat_id, file.file_content, file.file_name)
    end)
    |> to_outcome()
  end

  defp deliver_downloaded_files(%DownloadContext{} = context, files) do
    safe_upload_result(fn ->
      GoogleDrive.upload_files(context.chat_id, files)
    end)
    |> to_outcome()
  end

  defp safe_upload_result(upload_fun) do
    upload_fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp to_outcome({:ok, _body}), do: ok()
  defp to_outcome({:error, :google_drive_not_logged_in}), do: ok()
  defp to_outcome({:error, reason}), do: error(reason)

  defp ok do
    %{channel: :google_drive, status: :ok, error_messages: []}
  end

  defp error(reason) do
    %{channel: :google_drive, status: :error, error_messages: [error_message(reason)]}
  end

  defp error_message(reason), do: "Send to google drive failed, #{format_error_reason(reason)}"

  defp format_error_reason(%{body: %{"error" => %{"message" => message}}})
       when is_binary(message),
       do: message

  defp format_error_reason(%{body: %{"message" => message}}) when is_binary(message), do: message

  defp format_error_reason(%{status: status, body: body}) do
    body_reason = format_error_reason(%{body: body})

    if body_reason == inspect(body) do
      "status #{status}, #{body_reason}"
    else
      body_reason
    end
  end

  defp format_error_reason(%{message: message}) when is_binary(message), do: message
  defp format_error_reason(%{body: body}), do: format_error_reason(body)

  defp format_error_reason(results) when is_list(results) do
    Enum.find_value(results, inspect(results), fn
      {:error, reason} -> format_error_reason(reason)
      _ -> nil
    end)
  end

  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_error_reason(reason), do: inspect(reason)
end
