defmodule Logflare.Backends.Adaptor.WebhookAdaptor do
  @moduledoc false
  use GenServer
  use TypedStruct

  alias Logflare.Backends

  @behaviour Logflare.Backends.Adaptor

  typedstruct do
    field(:config, %{
      url: String.t(),
      headers: map(),
      http: String.t()
    })
  end

  @impl Logflare.Backends.Adaptor
  def start_link({source, backend} = args) do
    GenServer.start_link(__MODULE__, args, name: Backends.via_source(source, __MODULE__, backend))
  end

  @impl GenServer
  def init({source, backend}) do
    args = %{
      config: backend.config,
      source: source,
      backend: backend
    }

    {:ok, _pipeline_pid} = __MODULE__.Pipeline.start_link(args)
    {:ok, %{}}
  end

  @impl Logflare.Backends.Adaptor
  def cast_config(params) do
    {%{}, %{url: :string, headers: :map, http: :string}}
    |> Ecto.Changeset.cast(params, [:url, :headers, :http])
    |> Logflare.Utils.default_field_value(:http, "http2")
  end

  @impl Logflare.Backends.Adaptor
  def execute_query(_ident, _query),
    do: {:error, :not_implemented}

  @impl Logflare.Backends.Adaptor
  def validate_config(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:url])
    |> Ecto.Changeset.validate_format(:url, ~r/https?\:\/\/.+/)
    |> Ecto.Changeset.validate_inclusion(:http, ["http1", "http2"])
  end

  # HTTP Client
  defmodule Client do
    @moduledoc false
    use Tesla, docs: false

    def send(opts) do
      adaptor =
        if Keyword.get(opts, :http) == "http1" do
          {Tesla.Adapter.Finch, name: Logflare.FinchDefaultHttp1, receive_timeout: 5_000}
        else
          {Tesla.Adapter.Finch, name: Logflare.FinchDefault, receive_timeout: 5_000}
        end

      opts =
        opts
        |> Keyword.put_new(:method, :post)
        |> Keyword.update(:headers, [], &Map.to_list/1)

      Tesla.client(
        [
          Tesla.Middleware.Telemetry,
          Tesla.Middleware.JSON
        ],
        adaptor
      )
      |> request(opts)
    end
  end

  # Broadway Pipeline
  defmodule Pipeline do
    @moduledoc false
    use Broadway
    alias Broadway.Message
    alias Logflare.Backends.BufferProducer
    alias Logflare.Backends.Adaptor.WebhookAdaptor.Client

    def start_link(args) do
      Broadway.start_link(__MODULE__,
        name: Backends.via_source(args.source, __MODULE__, args.backend),
        hibernate_after: 5_000,
        spawn_opt: [
          fullsweep_after: 100
        ],
        producer: [
          module:
            {BufferProducer,
             [
               backend: args.backend,
               source: args.source
             ]},
          transformer: {__MODULE__, :transform, []},
          concurrency: 1
        ],
        processors: [
          default: [concurrency: 3, min_demand: 1]
        ],
        batchers: [
          http: [concurrency: 6, batch_size: 250]
        ],
        context: Map.take(args, [:config])
      )
    end

    # see the implementation for Backends.via_source/2 for how tuples are used to identify child processes
    def process_name({:via, module, {registry, identifier}}, base_name) do
      new_identifier = Tuple.append(identifier, base_name)
      {:via, module, {registry, new_identifier}}
    end

    def handle_message(_processor_name, message, _context) do
      message
      |> Message.put_batcher(:http)
    end

    def handle_batch(:http, messages, _batch_info, context) do
      payload = for %{data: le} <- messages, do: le.body
      process_data(payload, context)
      messages
    end

    defp process_data(log_event_bodies, %{config: %{} = config}) do
      Client.send(
        url: config.url,
        body: log_event_bodies,
        headers: config[:headers] || %{},
        http: config.http
      )
    end

    # Broadway transformer for custom producer
    def transform(event, _opts) do
      %Message{
        data: event,
        acknowledger: {__MODULE__, :ack_id, :ack_data}
      }
    end

    def ack(_ack_ref, _successful, _failed) do
      # TODO: re-queue failed
    end
  end
end
