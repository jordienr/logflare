defmodule Logflare.Backends.IngestEventQueue.QueueJanitor do
  @moduledoc """
  Performs cleanup actions for a private :ets queue

  Periodically purges the queue of `:ingested` events.

  If total events exceeds a max threshold, it will purge all events from the queue.
  This is in the case of sudden bursts of events that do not get cleared fast enough.
  It also acts as a failsafe for any potential runaway queue buildup from bugs.
  """
  use GenServer
  alias Logflare.Backends.IngestEventQueue
  require Logger
  @default_interval 1_000
  @default_remainder 100
  @default_max 50_000
  @default_purge_ratio 0.1

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    bid = if backend = Keyword.get(opts, :backend), do: backend.id
    source = Keyword.get(opts, :source)

    state = %{
      source_id: source.id,
      backend_id: bid,
      interval: Keyword.get(opts, :interval, @default_interval),
      remainder: Keyword.get(opts, :remainder, @default_remainder),
      max: Keyword.get(opts, :max, @default_max),
      purge_ratio: Keyword.get(opts, :purge_ratio, @default_purge_ratio)
    }

    schedule(state.interval)
    {:ok, state}
  end

  def handle_info(:work, state) do
    sid_bid = {state.source_id, state.backend_id}
    # clear out all ingested events
    IngestEventQueue.truncate(sid_bid, :ingested, state.remainder)

    # safety measure, drop all if still exceed
    all_size = IngestEventQueue.get_table_size(sid_bid)

    if all_size > state.max do
      remainder = round((1 - state.purge_ratio) * all_size)
      IngestEventQueue.truncate(sid_bid, :all, remainder)

      Logger.warning(
        "IngestEventQueue private :ets buffer exceeded max for source id=#{state.source_id}, dropping #{all_size} events",
        backend_id: state.backend_id
      )
    end

    schedule(state.interval)
    {:noreply, state}
  end

  defp schedule(interval) do
    Process.send_after(self(), :work, interval)
  end
end
