defmodule Forge.Runner.Streaming do
  @moduledoc """
  Streaming runner with backpressure and async stage support.

  Implements lazy evaluation with Task.async_stream for memory-efficient
  processing of large datasets.

  ## Features

  - Lazy sample generation (pull model)
  - Backpressure via bounded Task mailboxes
  - Async I/O-bound stages with concurrency control
  - Memory bounded to O(concurrency), not O(dataset_size)

  ## Usage

      # Returns a stream (lazy evaluation)
      stream = Forge.Runner.Streaming.run(pipeline, concurrency: 10)

      # Consume with backpressure
      samples = stream |> Enum.take(1000) |> Enum.to_list()

      # Or process lazily
      stream
      |> Stream.each(&process_sample/1)
      |> Stream.run()
  """

  alias Forge.{Sample, Stage}
  require Logger

  @doc """
  Run pipeline and return a stream of processed samples.

  ## Options

    * `:concurrency` - Max concurrent async tasks (default: System.schedulers_online())
    * `:storage` - Storage adapter module (default: nil, no persistence)
    * `:storage_opts` - Options for storage adapter
  """
  def run(pipeline, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    storage = Keyword.get(opts, :storage)
    storage_opts = Keyword.get(opts, :storage_opts, [])

    # Initialize storage if configured
    storage_state =
      if storage do
        case storage.init(storage_opts) do
          {:ok, state} -> state
          {:error, reason} -> raise "Failed to initialize storage: #{inspect(reason)}"
        end
      else
        nil
      end

    # Generate sample stream from source
    pipeline
    |> generate_sample_stream()
    |> apply_stages(pipeline.stages, concurrency)
    |> compute_measurements(pipeline.measurements)
    |> maybe_persist(storage, storage_state)
  end

  # Private Functions

  defp generate_sample_stream(pipeline) do
    # Use unfold to emit samples one by one
    Stream.unfold(
      (fn ->
         # Initialize source
         case pipeline.source_module.init(pipeline.source_opts) do
           {:ok, state} -> {pipeline.source_module, state, pipeline.name, []}
           {:error, reason} -> raise "Failed to initialize source: #{inspect(reason)}"
         end
       end).(),
      fn
        nil ->
          nil

        {source_module, source_state, pipeline_name, []} ->
          # Buffer is empty, fetch next batch
          case source_module.fetch(source_state) do
            {:ok, raw_samples, new_state} ->
              samples =
                raw_samples
                |> List.wrap()
                |> Enum.map(fn data ->
                  Sample.new(
                    id: generate_sample_id(),
                    pipeline: pipeline_name,
                    data: data
                  )
                end)

              case samples do
                [] ->
                  # Empty batch, try fetching again
                  {source_module, new_state, pipeline_name, []}
                  |> then(fn state -> generate_next_sample(state) end)

                [first | rest] ->
                  {first, {source_module, new_state, pipeline_name, rest}}
              end

            {:done, _final_state} ->
              nil

            {:error, reason} ->
              Logger.error("Source fetch error: #{inspect(reason)}")
              nil
          end

        {source_module, source_state, pipeline_name, [first | rest]} ->
          # Return buffered sample
          {first, {source_module, source_state, pipeline_name, rest}}
      end
    )
  end

  defp generate_next_sample({source_module, source_state, pipeline_name, []}) do
    case source_module.fetch(source_state) do
      {:ok, raw_samples, new_state} ->
        samples =
          raw_samples
          |> List.wrap()
          |> Enum.map(fn data ->
            Sample.new(
              id: generate_sample_id(),
              pipeline: pipeline_name,
              data: data
            )
          end)

        case samples do
          [] -> generate_next_sample({source_module, new_state, pipeline_name, []})
          [first | rest] -> {first, {source_module, new_state, pipeline_name, rest}}
        end

      {:done, _} ->
        nil

      {:error, reason} ->
        Logger.error("Source fetch error: #{inspect(reason)}")
        nil
    end
  end

  defp apply_stages(stream, stages, default_concurrency) do
    Enum.reduce(stages, stream, fn {stage_module, _opts}, acc ->
      if Stage.async?(stage_module) do
        # Async I/O-bound stage
        concurrency = min(Stage.concurrency(stage_module), default_concurrency)
        timeout = Stage.timeout(stage_module)

        Task.async_stream(
          acc,
          fn sample -> apply_stage(sample, stage_module) end,
          max_concurrency: concurrency,
          ordered: false,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Stream.filter(fn
          {:ok, {:ok, _sample}} ->
            true

          {:ok, {:skip, _reason}} ->
            false

          {:ok, {:error, reason}} ->
            Logger.error("Stage #{stage_module} error: #{inspect(reason)}")
            false

          {:exit, reason} ->
            Logger.error("Stage #{stage_module} timeout/exit: #{inspect(reason)}")
            false
        end)
        |> Stream.map(fn {:ok, {:ok, sample}} -> sample end)
      else
        # Sync CPU-bound stage
        acc
        |> Stream.map(fn sample ->
          case apply_stage(sample, stage_module) do
            {:ok, processed} ->
              {:ok, processed}

            {:skip, reason} ->
              {:skip, reason}

            {:error, reason} ->
              Logger.error("Stage #{stage_module} error: #{inspect(reason)}")
              {:error, reason}
          end
        end)
        |> Stream.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Stream.map(fn {:ok, sample} -> sample end)
      end
    end)
  end

  defp apply_stage(sample, stage_module) do
    stage_module.process(sample)
  rescue
    e ->
      Logger.error(
        "Stage #{stage_module} crashed: #{Exception.format(:error, e, __STACKTRACE__)}"
      )

      {:error, e}
  end

  defp compute_measurements(stream, measurements) do
    # For streaming, we compute measurements inline per sample
    # (batch measurements would require chunking)
    if Enum.empty?(measurements) do
      stream
      |> Stream.map(&Sample.mark_ready/1)
    else
      stream
      |> Stream.map(fn sample ->
        # Compute sync measurements
        measurements_map =
          Enum.reduce(measurements, %{}, fn {module, _opts}, acc ->
            # Note: This assumes measurements can work on single samples
            # For batch measurements, we'd need Stream.chunk_every
            case module.compute([sample]) do
              {:ok, result} ->
                Map.merge(acc, result)

              {:error, reason} ->
                Logger.error("Measurement #{module} failed: #{inspect(reason)}")
                acc
            end
          end)

        sample
        |> Sample.add_measurements(measurements_map)
        |> Sample.mark_measured()
        |> Sample.mark_ready()
      end)
    end
  end

  defp maybe_persist(stream, nil, _state), do: stream

  defp maybe_persist(stream, storage_module, storage_state) do
    # Use a tap pattern - persist in background but keep stream flowing
    # We'll chunk and store asynchronously to avoid blocking the stream
    stream
    |> Stream.chunk_every(100)
    |> Stream.flat_map(fn chunk ->
      # Store chunk (fire-and-forget for streaming)
      case storage_module.store(chunk, storage_state) do
        {:ok, _new_state} ->
          :ok

        {:error, reason} ->
          Logger.error("Storage failed: #{inspect(reason)}")
      end

      # Always return the chunk to continue the stream
      chunk
    end)
  end

  defp generate_sample_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
