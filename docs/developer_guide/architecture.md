# Nixidy Architecture Guide for Contributors

This guide provides a comprehensive overview of the nixidy codebase to help new contributors understand the project structure, key concepts, and development workflow.

## Table of Contents

- [Project Structure](#project-structure)
- [Core Concepts](#core-concepts)
- [Module System Deep Dive](#module-system-deep-dive)
- [Library Functions](#library-functions)
- [Code Generators](#code-generators)
- [Testing Framework](#testing-framework)
- [Development Workflow](#development-workflow)
- [Adding New Features](#adding-new-features)
- [Common Tasks](#common-tasks)
- [Code Style](#code-style)

## Project Structure

```
nixidy/
├── cli/                    # Python-based CLI tool
├── docs/                   # Documentation (MkDocs)
│   └── user_guide/         # User-facing documentation
├── lib/                    # Nix function library
│   ├── default.nix         # Library entry point
│   ├── helm.nix            # Helm-related functions
│   ├── kube.nix            # Kubernetes utility functions
│   ├── kustomize.nix       # Kustomize-related functions
│   └── tests.nix           # Library unit tests
├── modules/                # NixOS-style modules
│   ├── applications/       # Application submodule
│   │   ├── default.nix     # Application options and config
│   │   ├── helm.nix        # Helm release processing
│   │   ├── kustomize.nix   # Kustomize processing
│   │   ├── lib.nix         # Application helper functions
│   │   └── yamls.nix       # Raw YAML processing
│   ├── generated/          # Auto-generated resource options
│   │   ├── argocd.nix      # ArgoCD CRD options
│   │   └── k8s/            # Kubernetes resource options by version
│   ├── testing/            # Testing framework modules
│   │   ├── default.nix     # Test suite configuration
│   │   └── eval.nix        # Test evaluation logic
│   ├── applications.nix    # Main applications option
│   ├── build.nix           # Build output packages
│   ├── default.nix         # Module entry point
│   ├── extra-files.nix     # Extra files configuration
│   ├── modules.nix         # Module list
│   ├── nixidy.nix          # Core nixidy options
│   └── templates.nix       # Template system
├── nixidy/                 # Legacy bash CLI (deprecated)
├── pkgs/                   # Nix packages and generators
│   └── generators/         # CRD and K8s schema generators
│       ├── crd2jsonschema.py   # CRD to JSON schema converter
│       ├── default.nix         # Generator entry point
│       ├── generator.nix       # Nix options generator
│       └── versions.nix        # Kubernetes versions config
├── tests/                  # Module unit tests
│   ├── helm/               # Helm-specific tests
│   ├── kustomize/          # Kustomize-specific tests
│   └── *.nix               # Individual test files
├── flake.nix               # Nix flake definition
└── default.nix             # Non-flake entry point
```

## Core Concepts

### 1. NixOS Module System

Nixidy is built on top of the NixOS module system. If you're unfamiliar with it, read the [NixOS Module System documentation](https://nixos.org/manual/nixos/stable/#sec-writing-modules) first.

Key concepts:
- **Options**: Define the configuration interface with types, defaults, and descriptions
- **Config**: Contains the actual configuration values after module evaluation
- **Imports**: Modules can import other modules to extend functionality
- **Special Args**: Additional arguments passed to all modules (`lib`, `pkgs`, `config`, etc.)

### 2. Application Lifecycle

```
User Config → Module Evaluation → Resource Processing → Manifest Generation → Output
```

1. **User Configuration**: Nix files defining applications and resources
2. **Module Evaluation**: NixOS module system merges all configurations
3. **Resource Processing**: Helm/Kustomize/YAML converted to typed resources
4. **Manifest Generation**: Resources serialized to YAML files
5. **Output**: Packages created for different deployment strategies

### 3. Resource Type System

Resources are organized by Group/Version/Kind (GVK):

```nix
resources.<group>.<version>.<kind>.<name> = { ... };

# Examples:
resources.core.v1.ConfigMap.my-config = { ... };
resources.apps.v1.Deployment.nginx = { ... };
resources."networking.k8s.io".v1.Ingress.main = { ... };
```

Aliases provide convenient access:
```nix
resources.configMaps.my-config = { ... };      # → core.v1.ConfigMap
resources.deployments.nginx = { ... };          # → apps.v1.Deployment
resources.ingresses.main = { ... };             # → networking.k8s.io.v1.Ingress
```

### 4. Processing Pipeline

All input sources are normalized to typed nix resources:

```
┌─────────────────┐
│  Helm Charts    │──┐
├─────────────────┤  │
│  Kustomize      │──┤──→ [GVK Classification] ──→ [Typed Nix Resources] ──→ [YAML Output]
├─────────────────┤  │
│  Raw YAML       │──┘
└─────────────────┘
```

## Module System Deep Dive

### Main Modules

#### `modules/applications.nix`

Defines the top-level `applications` option:

```nix
{
  options.applications = mkOption {
    type = attrsOf (submoduleWith {
      modules = [ ./applications ] ++ config.nixidy.applicationImports;
      specialArgs.nixidyDefaults = config.nixidy.defaults;
    });
  };
}
```

Key responsibilities:
- Creates application submodules
- Manages Kubernetes version selection (`nixidy.k8sVersion`)
- Imports generated resource options

#### `modules/nixidy.nix`

Core nixidy configuration:

```nix
{
  options.nixidy = {
    env = mkOption { ... };                    # Environment name
    target.repository = mkOption { ... };      # Git repository URL
    target.branch = mkOption { ... };          # Target branch
    target.rootPath = mkOption { ... };        # Root path for manifests
    defaults = { ... };                        # Default settings
    appOfApps = { ... };                       # Bootstrap app config
    charts = mkOption { ... };                 # Helm chart sources
  };
}
```

Also handles:
- App-of-apps pattern generation
- Chart attribute set building
- Public apps list management

#### `modules/applications/default.nix`

Defines individual application options:

```nix
{
  options = {
    name = mkOption { ... };
    namespace = mkOption { ... };
    createNamespace = mkOption { ... };
    syncPolicy = { ... };
    destination = { ... };
    resources = { ... };  # Typed Kubernetes resources
    objects = mkOption { ... };  # Internal: final resource list
  };
}
```

Key responsibilities:
- Application metadata and settings
- Sync policy configuration
- Resource type registration
- Final object list generation

#### `modules/applications/helm.nix`

Helm chart integration:

```nix
{
  options.helm.releases = mkOption {
    type = attrsOf (submodule {
      options = {
        chart = mkOption { ... };
        values = mkOption { ... };
        transformer = mkOption { ... };
      };
    });
  };
}
```

Processing flow:
1. `helm.buildHelmChart` templates the chart
2. `builtins.readFile` reads output
3. `kube.fromYAML` parses to attribute sets
4. `transformer` function applied
5. Objects grouped by GVK
6. Added to `resources` or `objects`

#### `modules/applications/kustomize.nix`

Kustomize integration (similar pattern to Helm):

```nix
{
  options.kustomize.applications = mkOption {
    type = attrsOf (submodule {
      options = {
        kustomization.src = mkOption { ... };
        kustomization.path = mkOption { ... };
        transformer = mkOption { ... };
      };
    });
  };
}
```

#### `modules/applications/yamls.nix`

Raw YAML manifest support:

```nix
{
  options.yamls = mkOption {
    type = listOf str;
    description = "List of YAML manifest strings";
  };
}
```

#### `modules/build.nix`

Creates output packages:

- `environmentPackage`: All application manifests combined
- `activationPackage`: For `nixidy switch` operations
- `declarativePackage`: For `kubectl apply --prune`
- `bootstrapPackage`: App-of-apps manifest

#### `modules/templates.nix`

Template system for reusable patterns:

```nix
{
  options.templates = mkOption {
    type = attrsOf (submodule {
      options = {
        options = mkOption { ... };  # Template parameters
        output = mkOption { ... };   # Resource generator function
      };
    });
  };
}
```

Templates become application imports, allowing:
```nix
applications.myapp.templates.webApp.frontend = {
  image = "nginx:latest";
  replicas = 3;
};
```

### Helper Functions (`modules/applications/lib.nix`)

```nix
{
  # Extract Group/Version/Kind from Kubernetes object
  getGVK = object: {
    group = ...;   # "core" for v1, otherwise first part of apiVersion
    version = ...; # Version string
    kind = ...;    # Kind string
  };

  # Flatten *List objects (e.g., ConfigMapList → [ConfigMap, ...])
  flattenListObjects = ...;
}
```

## Library Functions

### Entry Point (`lib/default.nix`)

Extends `nixpkgs.lib` with nixidy functions:

```nix
lib.extend (self: old: {
  kustomize = import ./kustomize.nix { ... };
  helm = import ./helm.nix { ... };
  kube = import ./kube.nix { ... };
})
```

### Helm Functions (`lib/helm.nix`)

| Function | Description |
|----------|-------------|
| `downloadHelmChart` | Downloads chart from Helm registry |
| `buildHelmChart` | Templates chart with values |
| `getChartValues` | Parses chart's default values.yaml |
| `mkChartAttrs` | Creates chart attrset from directory structure |

### Kube Functions (`lib/kube.nix`)

| Function | Description |
|----------|-------------|
| `fromYAML` | Parses YAML string to attribute sets |
| `fromOctal` | Converts octal string to integer |
| `removeLabels` | Removes specified labels from manifests |

### Kustomize Functions (`lib/kustomize.nix`)

| Function | Description |
|----------|-------------|
| `buildKustomization` | Builds kustomize application |

## Code Generators

### Overview (`pkgs/generators/`)

Nixidy generates typed Nix options from:
1. Kubernetes OpenAPI schemas
2. Custom Resource Definitions (CRDs)

### Kubernetes Schema Generation

`pkgs/generators/default.nix` handles K8s schema generation:

1. Fetches Kubernetes source for each version in `versions.nix`
2. Extracts OpenAPI swagger spec
3. Generates namespaced resource info
4. Produces Nix options via `generator.nix`

Output: `modules/generated/k8s/v1.XX.nix`

### CRD Generation

Two entry points:

#### `fromCRD`
```nix
fromCRD {
  name = "cilium";
  src = pkgs.fetchFromGitHub { ... };
  crds = [ "path/to/crd.yaml" ];
  namePrefix = "";           # Optional prefix for attribute names
  attrNameOverrides = { };   # Manual name overrides
  skipCoerceToList = { };    # Skip list coercion for specific fields
}
```

#### `fromChartCRD`
```nix
fromChartCRD {
  name = "cert-manager";
  chartAttrs = { repo = "..."; chart = "..."; version = "..."; };
  crds = [ "Certificate" ];  # Filter by kind
}
```

### CRD Processing (`crd2jsonschema.py`)

Python script that:
1. Reads CRD YAML files
2. Extracts OpenAPI v3 schemas
3. Flattens `$ref` references
4. Outputs JSON schema for `generator.nix`

## Testing Framework

### Module Tests (`tests/`)

Located in `tests/`, using nixidy's testing framework.

#### Test Structure

```nix
# tests/my-feature.nix
{
  lib,
  config,
  ...
}:
let
  apps = config.applications;
in
{
  # Define test configuration
  applications.test1 = {
    namespace = "test";
    resources.configMaps.cm.data.FOO = "bar";
  };

  # Define test assertions
  test = {
    name = "my feature test";
    description = "Description of what's being tested";
    assertions = [
      {
        description = "ConfigMap should have FOO key";
        expression = (elemAt apps.test1.objects 0).data;
        expected = { FOO = "bar"; };
      }
      {
        description = "Custom assertion function";
        expression = apps.test1.objects;
        assertion = objs: length objs == 1;
      }
    ];
  };
}
```

#### Running Tests

```sh
# Run module tests
nix run .#moduleTests

# Run library tests
nix run .#libTests
```

#### Test Registration (`tests/default.nix`)

```nix
{
  testing = {
    name = "nixidy modules";
    tests = [
      ./configmap.nix
      ./create-namespace.nix
      ./helm/with-values.nix
      # ... more tests
    ];
  };
}
```

### Library Tests (`lib/tests.nix`)

Uses `lib.runTests` pattern:

```nix
{
  kube = {
    fromYAML = {
      testSingleObject = {
        expr = lib.kube.fromYAML "...";
        expected = [ { ... } ];
      };
    };
    removeLabels = {
      testLabelPresent = {
        expr = lib.kube.removeLabels ["helm.sh/chart"] { ... };
        expected = { ... };
      };
    };
  };
}
```

## Development Workflow

### Prerequisites

- Nix with flakes enabled
- Basic understanding of NixOS module system

### Common Commands

```sh
# Format code
nix fmt

# Run static linter
nix run .#staticCheck

# Run library tests
nix run .#libTests

# Run module tests
nix run .#moduleTests

# Generate Kubernetes modules
nix run .#generate

# Serve documentation locally
nix run .#docsServe
```

### Development Cycle

1. **Make changes** to modules or library
2. **Write tests** for new functionality
3. **Run tests** to verify changes
4. **Format code** with `nix fmt`
5. **Run linter** with `nix run .#staticCheck`
6. **Test manually** with a sample configuration

### Manual Testing

Create a test configuration:

```nix
# test-config.nix
{
  nixidy.target = {
    repository = "https://github.com/test/repo.git";
    branch = "main";
  };

  applications.test = {
    namespace = "test";
    createNamespace = true;
    resources.deployments.nginx.spec = {
      selector.matchLabels.app = "nginx";
      template = {
        metadata.labels.app = "nginx";
        spec.containers.nginx.image = "nginx:latest";
      };
    };
  };
}
```

Build and inspect:

```sh
nix run .#cli -- build .#test
tree result/
cat result/test/Deployment-nginx.yaml
```

## Adding New Features

### Adding a New Application Option

1. **Define the option** in `modules/applications/default.nix`:

```nix
{
  options = {
    myNewOption = mkOption {
      type = types.bool;
      default = false;
      description = "Description of the option.";
    };
  };
}
```

2. **Use the option** in config:

```nix
{
  config = lib.mkIf config.myNewOption {
    # Configuration when option is enabled
  };
}
```

3. **Write tests** in `tests/`:

```nix
# tests/my-new-option.nix
{
  applications.test1 = {
    myNewOption = true;
    # ...
  };

  test = {
    name = "my new option";
    description = "Test the new option";
    assertions = [ ... ];
  };
}
```

4. **Register test** in `tests/default.nix`

5. **Document** in `docs/user_guide/`

### Adding a New Library Function

1. **Add function** to appropriate file in `lib/`:

```nix
# lib/kube.nix
{
  myNewFunction =
    # Parameter description
    param:
    # Implementation
    ...;
}
```

2. **Add documentation** as comments:

```nix
/*
  Description of function.

  Type:
    myNewFunction :: ParamType -> ReturnType

  Example:
    myNewFunction "input"
    => "output"
*/
myNewFunction = ...;
```

3. **Write tests** in `lib/tests.nix`:

```nix
{
  kube = {
    myNewFunction = {
      testBasicCase = {
        expr = lib.kube.myNewFunction "input";
        expected = "output";
      };
    };
  };
}
```

### Adding a New Resource Processor

Similar to Helm/Kustomize, create a new module:

1. **Create module** `modules/applications/myprocessor.nix`:

```nix
{
  nixidyDefaults,
  lib,
  config,
  ...
}:
let
  helpers = import ./lib.nix lib;
in
{
  options.myProcessor = mkOption {
    type = with types; attrsOf (submodule { ... });
  };

  config = {
    # Process inputs and add to resources/objects
    resources = mkMerge [ ... ];
    objects = [ ... ];
  };
}
```

2. **Import** in `modules/applications/default.nix`:

```nix
{
  imports = [
    ./helm.nix
    ./kustomize.nix
    ./yamls.nix
    ./myprocessor.nix  # Add here
  ];
}
```

## Common Tasks

### Updating Kubernetes Versions

1. Edit `pkgs/generators/versions.nix`:

```nix
{
  "1.34.0" = {
    hash = "sha256-...";
    spec = "api/openapi-spec/swagger.json";
    discovery = {
      core = "api/discovery/core_v1.json";
      aggregated = "api/discovery/aggregated_v2.json";
    };
  };
}
```

2. Regenerate:

```sh
nix run .#generate
```

3. Update default version in `modules/applications.nix` if needed

### Adding a New Sync Option

1. Add option in `modules/applications/default.nix` under `syncPolicy.syncOptions`:

```nix
{
  syncPolicy.syncOptions.myOption = mkOption {
    type = types.bool;
    default = false;
    apply = val: if val then "MyOption=true" else null;
    description = "Description";
  };
}
```

2. The `apply` function converts to ArgoCD sync option format

3. `convertSyncOptionsList` automatically collects non-null options

### Debugging Module Evaluation

Use `builtins.trace` for debugging:

```nix
{
  config = lib.mkMerge [
    (builtins.trace "Processing ${config.name}" {
      # ...
    })
  ];
}
```

Or use `lib.debug.traceValSeqN`:

```nix
{
  objects = lib.debug.traceValSeqN 2 config.resources;
}
```

## Code Style

### Nix

- **Format**: Use `nix fmt` (nixfmt-rfc-style)
- **Sorting**: Keep attribute sets alphabetically sorted
- **Inherit**: Use `inherit` where possible to reduce verbosity
- **Imports**: Group imports logically
- **Types**: Use specific types over `types.anything` when possible

```nix
# Good
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (config) namespace;
  inherit (lib) mkOption types;
in
{
  options.myOption = mkOption {
    type = types.str;
    default = "";
  };
}

# Avoid
{lib, config, pkgs, ...}: let
  namespace = config.namespace;
in {
  options.myOption = lib.mkOption {
    type = lib.types.str;
    default = "";
  };
}
```

### Python (CLI)

- Follow PEP 8 guidelines
- Use type hints for all function signatures
- Document public functions with docstrings

### Documentation

- Use MkDocs syntax
- Include code examples with syntax highlighting
- Cross-reference related documentation
- Keep language clear and concise

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/arnarg/nixidy/issues)
- **Discussions**: [GitHub Discussions](https://github.com/arnarg/nixidy/discussions)
- **Documentation**: [nixidy.dev](https://nixidy.dev)

## Summary

Key files for different tasks:

| Task | Files |
|------|-------|
| Add application option | `modules/applications/default.nix` |
| Add nixidy option | `modules/nixidy.nix` |
| Add library function | `lib/*.nix` |
| Add resource processor | `modules/applications/` |
| Add template feature | `modules/templates.nix` |
| Modify build output | `modules/build.nix` |
| Add K8s version | `pkgs/generators/versions.nix` |
| Write module test | `tests/*.nix`, `tests/default.nix` |
| Write library test | `lib/tests.nix` |

Welcome to the nixidy project! We look forward to your contributions.
