defmodule LogflareWeb.LogChannel do
  use LogflareWeb, :channel

  alias Logflare.{Logs, Sources, Source}

  def join("ingest:" <> source_uuid, _payload, socket) do
    case Sources.Cache.get_by(token: source_uuid) do
      %Source{} = source ->
        send(self, {:notify, %{message: "Ready! Can we haz all your datas?"}})
        socket = socket |> assign(:source, source)
        {:ok, socket}

      nil ->
        {:error, socket}
    end
  end

  def handle_in("batch", %{"batch" => batch}, socket) when is_list(batch) do
    case Logs.ingest_logs(log_params_batch, source) do
      :ok ->
        push(socket, "batch", %{message: "Handled batch"})
        {:noreply, socket}

      {:error, errors} ->
        push(socket, "batch", %{message: "Batch error", errors: errors})
        {:noreply, socket}
    end
  end

  def handle_in("ping", payload, socket) do
    push(socket, "pong", %{message: "Pong"})
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    send(
      self,
      {:notify,
       %{
         message: "Unhandled event type. Please verify.",
         echo_payload: inspect(payload)
       }}
    )

    {:noreply, socket}
  end

  def handle_info({:notify, payload}, socket) do
    push(socket, "notify", payload)
    {:noreply, socket}
  end
end
