defmodule Forge.Telemetry.OTel do
  @moduledoc """
  OpenTelemetry integration for Forge (optional).

  This module provides OpenTelemetry tracing integration for Forge pipelines.
  It creates distributed traces with spans for pipeline runs and stage executions.

  ## Setup

  To use this module, add OpenTelemetry dependencies to your `mix.exs`:

      def deps do
        [
          {:opentelemetry, "~> 1.3"},
          {:opentelemetry_exporter, "~> 1.6"}
        ]
      end

  Then configure it in your application:

      # config/runtime.exs
      config :opentelemetry,
        resource: %{
          service_name: "my_forge_app",
          service_version: "1.0.0"
        }

      config :forge, :telemetry,
        reporters: [Forge.Telemetry.OTel]

  ## Spans Created

  - `forge.pipeline` - Full pipeline execution
  - `forge.stage` - Individual stage execution

  ## Span Attributes

  Pipeline spans include:
  - `forge.pipeline.id` - Pipeline identifier
  - `forge.run.id` - Run identifier
  - `forge.pipeline.name` - Pipeline name
  - `forge.pipeline.outcome` - Completion outcome
  - `forge.pipeline.duration_ms` - Duration in milliseconds

  Stage spans include:
  - `forge.stage.name` - Stage name
  - `forge.sample.id` - Sample identifier
  - `forge.stage.outcome` - Execution outcome
  - `forge.stage.duration_ms` - Duration in milliseconds
  - `forge.stage.error_type` - Error classification (if failed)
  """

  @doc """
  Attaches telemetry handlers for OpenTelemetry integration.

  This function should be called during application startup, typically by
  adding it to the telemetry reporters configuration.
  """
  def attach do
    if Code.ensure_loaded?(OpenTelemetry.Tracer) do
      events = [
        [:forge, :pipeline, :start],
        [:forge, :pipeline, :stop],
        [:forge, :stage, :start],
        [:forge, :stage, :stop]
      ]

      :telemetry.attach_many(
        "forge-otel",
        events,
        &handle_event/4,
        %{}
      )

      :ok
    else
      require Logger

      Logger.warning(
        "OpenTelemetry not available. Install :opentelemetry to enable tracing. " <>
          "Forge will continue to work without tracing."
      )

      :ok
    end
  end

  # Event handlers - always define a fallback
  defp handle_event(event, measurements, metadata, config) do
    if Code.ensure_loaded?(OpenTelemetry.Tracer) do
      do_handle_event(event, measurements, metadata, config)
    else
      :ok
    end
  end

  # Only try to use OpenTelemetry if it's available at runtime
  defp do_handle_event([:forge, :pipeline, :start], _measurements, metadata, _config) do
    apply(OpenTelemetry.Tracer, :start_span, [
      "forge.pipeline",
      %{
        attributes: %{
          "forge.pipeline.id" => metadata.pipeline_id,
          "forge.run.id" => metadata.run_id,
          "forge.pipeline.name" => to_string(metadata.name)
        }
      }
    ])
  end

  defp do_handle_event([:forge, :pipeline, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    apply(OpenTelemetry.Tracer, :set_attributes, [
      %{
        "forge.pipeline.outcome" => to_string(metadata.outcome),
        "forge.pipeline.duration_ms" => duration_ms,
        "forge.pipeline.samples_processed" => measurements.samples_processed
      }
    ])

    apply(OpenTelemetry.Tracer, :end_span, [])
  end

  defp do_handle_event([:forge, :stage, :start], _measurements, metadata, _config) do
    apply(OpenTelemetry.Tracer, :start_span, [
      "forge.stage",
      %{
        attributes: %{
          "forge.stage.name" => to_string(metadata.stage),
          "forge.sample.id" => metadata.sample_id
        }
      }
    ])
  end

  defp do_handle_event([:forge, :stage, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    attributes = %{
      "forge.stage.outcome" => to_string(metadata.outcome),
      "forge.stage.duration_ms" => duration_ms
    }

    attributes =
      if metadata[:error_type] do
        Map.put(attributes, "forge.stage.error_type", to_string(metadata.error_type))
      else
        attributes
      end

    apply(OpenTelemetry.Tracer, :set_attributes, [attributes])

    # Mark span as error if stage failed
    if metadata.outcome == :error do
      apply(OpenTelemetry.Tracer, :set_status, [:error, "Stage execution failed"])
    end

    apply(OpenTelemetry.Tracer, :end_span, [])
  end

  defp do_handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
