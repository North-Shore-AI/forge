defmodule Forge.Runner do
  @moduledoc """
  GenServer for executing pipelines.

  The Runner manages the execution of a pipeline, coordinating the source,
  stages, measurements, and storage.

  ## Usage

      # Start a runner
      {:ok, pid} = Forge.Runner.start_link(
        pipeline_module: MyApp.Pipelines,
        pipeline_name: :data_processing
      )

      # Run the pipeline
      samples = Forge.Runner.run(pid)

      # Get status
      status = Forge.Runner.status(pid)

      # Stop the runner
      :ok = Forge.Runner.stop(pid)
  """

  use GenServer
  require Logger

  alias Forge.Sample

  defmodule State do
    @moduledoc false
    defstruct [
      :pipeline_config,
      :source_state,
      :storage_state,
      status: :idle,
      samples_processed: 0,
      samples_skipped: 0,
      run_id: nil
    ]
  end

  # Client API

  @doc """
  Starts a pipeline runner.

  ## Options

    * `:pipeline_module` - Module containing pipeline definitions (required)
    * `:pipeline_name` - Name of the pipeline to run (required)
    * `:name` - GenServer name (optional)
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Runs the pipeline and returns processed samples.
  """
  def run(runner, timeout \\ :infinity) do
    GenServer.call(runner, :run, timeout)
  end

  @doc """
  Returns the current status of the runner.
  """
  def status(runner) do
    GenServer.call(runner, :status)
  end

  @doc """
  Stops the runner.
  """
  def stop(runner) do
    GenServer.stop(runner)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    pipeline_module = Keyword.fetch!(opts, :pipeline_module)
    pipeline_name = Keyword.fetch!(opts, :pipeline_name)

    pipeline_config = pipeline_module.__pipeline__(pipeline_name)

    unless pipeline_config do
      {:stop, {:error, "Pipeline #{pipeline_name} not found in #{pipeline_module}"}}
    else
      # Initialize source
      case pipeline_config.source_module.init(pipeline_config.source_opts) do
        {:ok, source_state} ->
          # Initialize storage if configured
          storage_state =
            if pipeline_config.storage_module do
              case pipeline_config.storage_module.init(pipeline_config.storage_opts) do
                {:ok, state} -> state
                {:error, reason} -> {:error, reason}
              end
            else
              nil
            end

          state = %State{
            pipeline_config: pipeline_config,
            source_state: source_state,
            storage_state: storage_state
          }

          {:ok, state}

        {:error, reason} ->
          {:stop, {:error, "Failed to initialize source: #{inspect(reason)}"}}
      end
    end
  end

  @impl true
  def handle_call(:run, _from, state) do
    run_id = generate_run_id()
    new_state = %{state | status: :running, run_id: run_id}

    case execute_pipeline(new_state) do
      {:ok, samples, final_state} ->
        final_state = %{final_state | status: :idle}
        {:reply, samples, final_state}

      {:error, reason} ->
        final_state = %{state | status: :error}
        {:reply, {:error, reason}, final_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      status: state.status,
      samples_processed: state.samples_processed,
      samples_skipped: state.samples_skipped,
      pipeline: state.pipeline_config.name,
      run_id: state.run_id
    }

    {:reply, status, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cleanup source
    if state.source_state do
      state.pipeline_config.source_module.cleanup(state.source_state)
    end

    # Cleanup storage
    if state.storage_state && state.pipeline_config.storage_module do
      state.pipeline_config.storage_module.cleanup(state.storage_state)
    end

    :ok
  end

  # Private Functions

  defp execute_pipeline(state) do
    # Fetch all samples from source
    case fetch_all_samples(state) do
      {:ok, raw_samples, new_source_state} ->
        # Convert to Sample structs
        samples =
          Enum.map(raw_samples, fn data ->
            Sample.new(
              id: generate_sample_id(),
              pipeline: state.pipeline_config.name,
              data: data
            )
          end)

        # Apply stages
        {processed, skipped} = apply_stages(samples, state.pipeline_config.stages)

        # Compute measurements
        measured = compute_measurements(processed, state.pipeline_config.measurements)

        # Store if storage configured
        new_storage_state =
          if state.pipeline_config.storage_module && measured != [] do
            case state.pipeline_config.storage_module.store(measured, state.storage_state) do
              {:ok, new_state} ->
                new_state

              {:error, reason} ->
                Logger.error("Storage failed: #{inspect(reason)}")
                state.storage_state
            end
          else
            state.storage_state
          end

        new_state = %{
          state
          | source_state: new_source_state,
            storage_state: new_storage_state,
            samples_processed: length(measured),
            samples_skipped: length(skipped)
        }

        {:ok, measured, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_samples(state) do
    fetch_all_samples(state.pipeline_config.source_module, state.source_state, [])
  end

  defp fetch_all_samples(source_module, source_state, acc) do
    case source_module.fetch(source_state) do
      {:ok, samples, new_state} ->
        fetch_all_samples(source_module, new_state, acc ++ samples)

      {:done, final_state} ->
        {:ok, acc, final_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_stages(samples, stages) do
    Enum.reduce(samples, {[], []}, fn sample, {processed, skipped} ->
      case process_through_stages(sample, stages) do
        {:ok, processed_sample} ->
          {[processed_sample | processed], skipped}

        {:skip, _reason} ->
          {processed, [Sample.mark_skipped(sample) | skipped]}

        {:error, reason} ->
          Logger.error("Stage error: #{inspect(reason)}")
          {processed, [Sample.mark_skipped(sample) | skipped]}
      end
    end)
    |> then(fn {processed, skipped} ->
      {Enum.reverse(processed), Enum.reverse(skipped)}
    end)
  end

  defp process_through_stages(sample, []) do
    {:ok, sample}
  end

  defp process_through_stages(sample, [{stage_module, _opts} | rest]) do
    case stage_module.process(sample) do
      {:ok, processed_sample} ->
        process_through_stages(processed_sample, rest)

      {:skip, reason} ->
        {:skip, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_measurements([], _measurements), do: []

  defp compute_measurements(samples, measurements) do
    # Separate sync and async measurements
    {sync_measurements, async_measurements} =
      Enum.split_with(measurements, fn {module, _opts} ->
        not Forge.Measurement.async?(module)
      end)

    # Compute synchronous measurements
    samples_with_measurements =
      if sync_measurements != [] do
        sync_results =
          Enum.reduce(sync_measurements, %{}, fn {module, _opts}, acc ->
            case module.compute(samples) do
              {:ok, result} ->
                Map.merge(acc, result)

              {:error, reason} ->
                Logger.error("Measurement #{module} failed: #{inspect(reason)}")
                acc
            end
          end)

        Enum.map(samples, fn sample ->
          sample
          |> Sample.add_measurements(sync_results)
          |> Sample.mark_measured()
          |> Sample.mark_ready()
        end)
      else
        Enum.map(samples, fn sample ->
          sample
          |> Sample.mark_measured()
          |> Sample.mark_ready()
        end)
      end

    # Start async measurements (fire and forget)
    if async_measurements != [] do
      Enum.each(async_measurements, fn {module, _opts} ->
        Task.start(fn ->
          case module.compute(samples) do
            {:ok, result} ->
              Logger.info("Async measurement #{module} completed: #{inspect(result)}")

            {:error, reason} ->
              Logger.error("Async measurement #{module} failed: #{inspect(reason)}")
          end
        end)
      end)
    end

    samples_with_measurements
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_sample_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
