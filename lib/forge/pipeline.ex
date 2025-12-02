defmodule Forge.Pipeline do
  @moduledoc """
  DSL for defining sample processing pipelines.

  Pipelines define how samples flow from a source through stages to storage,
  with measurements computed along the way.

  ## Usage

      defmodule MyApp.Pipelines do
        use Forge.Pipeline

        pipeline :data_processing do
          source Forge.Source.Static, data: [%{value: 1}, %{value: 2}]

          stage MyApp.Stages.Normalize
          stage MyApp.Stages.Validate, strict: true

          measurement MyApp.Measurements.Mean
          measurement MyApp.Measurements.StdDev

          storage Forge.Storage.ETS, table: :samples
        end
      end

  ## Pipeline Configuration

  Each pipeline must have:
  - A unique name (atom)
  - A source configuration

  Optional:
  - Stages (can have zero or more)
  - Measurements (can have zero or more)
  - Storage backend (if not specified, samples are not persisted)

  ## Retrieving Configuration

      config = MyApp.Pipelines.__pipeline__(:data_processing)
      all_pipelines = MyApp.Pipelines.__pipelines__()
  """

  defmodule Config do
    @moduledoc """
    Pipeline configuration structure.
    """

    @type stage_spec :: {module(), keyword()}
    @type measurement_spec :: {module(), keyword()}

    @type t :: %__MODULE__{
            name: atom(),
            source_module: module(),
            source_opts: keyword(),
            stages: [stage_spec()],
            measurements: [measurement_spec()],
            storage_module: module() | nil,
            storage_opts: keyword()
          }

    defstruct [
      :name,
      :source_module,
      source_opts: [],
      stages: [],
      measurements: [],
      storage_module: nil,
      storage_opts: []
    ]
  end

  defmacro __using__(_opts) do
    quote do
      import Forge.Pipeline
      Module.register_attribute(__MODULE__, :forge_pipelines, accumulate: false)
      Module.put_attribute(__MODULE__, :forge_pipelines, %{})

      @before_compile Forge.Pipeline
    end
  end

  defmacro __before_compile__(env) do
    pipelines = Module.get_attribute(env.module, :forge_pipelines) || %{}
    all_names = Map.keys(pipelines)

    # Generate a function for each pipeline
    pipeline_funs =
      for {name, config} <- pipelines do
        quote do
          def __pipeline__(unquote(name)) do
            unquote(Macro.escape(config))
          end
        end
      end

    quote do
      unquote(pipeline_funs)

      def __pipeline__(_name), do: nil

      def __pipelines__() do
        unquote(all_names)
      end
    end
  end

  defmacro pipeline(name, do: block) do
    quote bind_quoted: [name: name, block: Macro.escape(block, unquote: true)] do
      config = %Forge.Pipeline.Config{name: name}
      config = Forge.Pipeline.__eval_pipeline_block__(config, block)

      # Validate that source is configured
      unless config.source_module do
        raise ArgumentError, "Pipeline #{name} must specify a source"
      end

      # Store config in module attribute
      current_pipelines = Module.get_attribute(__MODULE__, :forge_pipelines) || %{}

      Module.put_attribute(
        __MODULE__,
        :forge_pipelines,
        Map.put(current_pipelines, name, config)
      )

      config
    end
  end

  @doc false
  def __eval_pipeline_block__(config, {:__block__, _, exprs}) do
    Enum.reduce(exprs, config, &__eval_pipeline_expr__(&2, &1))
  end

  def __eval_pipeline_block__(config, expr) do
    __eval_pipeline_expr__(config, expr)
  end

  defp __eval_pipeline_expr__(config, {:source, _, [module]}) do
    %{config | source_module: eval_module(module), source_opts: []}
  end

  defp __eval_pipeline_expr__(config, {:source, _, [module, opts]}) do
    %{config | source_module: eval_module(module), source_opts: opts}
  end

  defp __eval_pipeline_expr__(config, {:stage, _, [module]}) do
    %{config | stages: config.stages ++ [{eval_module(module), []}]}
  end

  defp __eval_pipeline_expr__(config, {:stage, _, [module, opts]}) do
    %{config | stages: config.stages ++ [{eval_module(module), opts}]}
  end

  defp __eval_pipeline_expr__(config, {:measurement, _, [module]}) do
    %{config | measurements: config.measurements ++ [{eval_module(module), []}]}
  end

  defp __eval_pipeline_expr__(config, {:measurement, _, [module, opts]}) do
    %{config | measurements: config.measurements ++ [{eval_module(module), opts}]}
  end

  defp __eval_pipeline_expr__(config, {:storage, _, [module]}) do
    %{config | storage_module: eval_module(module), storage_opts: []}
  end

  defp __eval_pipeline_expr__(config, {:storage, _, [module, opts]}) do
    %{config | storage_module: eval_module(module), storage_opts: opts}
  end

  defp __eval_pipeline_expr__(config, _unknown) do
    config
  end

  # Evaluate module alias to actual module atom
  defp eval_module({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp eval_module(module) when is_atom(module) do
    module
  end

  @doc false
  defmacro source(_module, _opts \\ []) do
    quote do
      :ok
    end
  end

  @doc false
  defmacro stage(_module, _opts \\ []) do
    quote do
      :ok
    end
  end

  @doc false
  defmacro measurement(_module, _opts \\ []) do
    quote do
      :ok
    end
  end

  @doc false
  defmacro storage(_module, _opts \\ []) do
    quote do
      :ok
    end
  end
end
