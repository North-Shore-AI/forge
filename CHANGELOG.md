# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `/v1` SampleIR and DatasetIR endpoints using shared `labeling_ir` structs with tenancy/namespace/lineage metadata.
- Compatibility handling for unknown request fields to maintain IR governance.

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

[Unreleased]: https://github.com/North-Shore-AI/forge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/North-Shore-AI/forge/releases/tag/v0.1.0
