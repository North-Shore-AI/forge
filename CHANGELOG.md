# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2025-12-02

### Added
- V1 Labeling IR API endpoints for `/v1/samples` and `/v1/datasets` using shared `labeling_ir` structs and new `SampleRecord`/`DatasetRecord` schemas that preserve tenancy, namespace, and lineage metadata.
- `Forge.API.Router` plug to route/parse requests, extract tenant headers, parse datetimes, and ignore unknown request fields while enforcing IR governance.
- `Forge.API.State` helpers and Labeling IR Ecto migrations enabling idempotent upserts and persistence for SampleIR and DatasetIR records.
- Optional `Forge.API.Server` supervisor to run Plug.Cowboy on port 4102 by default, plus new dependencies (`plug`, `plug_cowboy`, `labeling_ir`) supporting the API surface.
- API tests covering V1 routing, tenant isolation, and data handling.

## [0.1.0] - 2024-12-01

### Added

- Initial release
- `Forge.Source` behaviour for data sources
- `Forge.Source.Static` - static list source implementation
- `Forge.Source.Generator` - generator function source implementation
- `Forge.Stage` behaviour for pipeline transformation stages
- `Forge.Measurement` behaviour for computing sample measurements
- `Forge.Storage` behaviour for persistence
- `Forge.Storage.ETS` - in-memory ETS storage implementation
- `Forge.Sample` struct for sample data with lifecycle states
- `Forge.Pipeline` DSL for declarative pipeline configuration
- `Forge.Runner` GenServer for pipeline execution
- Comprehensive test suite using Supertester

[Unreleased]: https://github.com/North-Shore-AI/forge/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/North-Shore-AI/forge/releases/tag/v0.1.1
[0.1.0]: https://github.com/North-Shore-AI/forge/releases/tag/v0.1.0
