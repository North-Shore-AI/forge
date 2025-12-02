defmodule Forge do
  @moduledoc """
  A domain-agnostic sample factory library for generating, transforming,
  and computing measurements on arbitrary samples.

  Forge provides a flexible framework for building sample processing pipelines
  with pluggable sources, stages, measurements, and storage backends.

  ## Quick Start

      # Define a pipeline
      defmodule MyPipeline do
        use Forge.Pipeline

        pipeline :example do
          source Forge.Source.Static, data: [%{value: 1}, %{value: 2}]
          stage MyStage
          measurement MyMeasurement
          storage Forge.Storage.ETS, table: :samples
        end
      end

      # Run the pipeline
      {:ok, runner} = Forge.Runner.start_link(
        pipeline_module: MyPipeline,
        pipeline_name: :example
      )

      samples = Forge.Runner.run(runner)

  ## Core Concepts

  - **Sample**: Data structure representing a sample with id, data, measurements, and status
  - **Source**: Behaviour for generating or providing samples
  - **Pipeline**: Configuration of source, stages, measurements, and storage
  - **Stage**: Behaviour for transforming samples
  - **Measurement**: Behaviour for computing metrics on samples
  - **Storage**: Behaviour for persisting samples
  - **Runner**: GenServer that executes pipelines
  """

  alias Forge.{Sample, Runner}

  @doc """
  Creates a new sample with the given attributes.

  ## Examples

      iex> Forge.create_sample(id: "123", pipeline: :test, data: %{value: 42})
      %Forge.Sample{id: "123", pipeline: :test, data: %{value: 42}, status: :pending}
  """
  defdelegate create_sample(opts), to: Sample, as: :new

  @doc """
  Starts a pipeline runner.

  ## Options

    * `:pipeline_module` - Module containing pipeline definitions (required)
    * `:pipeline_name` - Name of the pipeline to run (required)
    * `:name` - GenServer name (optional)

  ## Examples

      {:ok, runner} = Forge.start_pipeline(
        pipeline_module: MyPipeline,
        pipeline_name: :my_pipeline
      )
  """
  defdelegate start_pipeline(opts), to: Runner, as: :start_link

  @doc """
  Runs a pipeline and returns the processed samples.

  ## Examples

      samples = Forge.run_pipeline(runner)
  """
  defdelegate run_pipeline(runner, timeout \\ :infinity), to: Runner, as: :run

  @doc """
  Gets the status of a running pipeline.

  ## Examples

      status = Forge.pipeline_status(runner)
  """
  defdelegate pipeline_status(runner), to: Runner, as: :status

  @doc """
  Stops a pipeline runner.

  ## Examples

      :ok = Forge.stop_pipeline(runner)
  """
  defdelegate stop_pipeline(runner), to: Runner, as: :stop
end
