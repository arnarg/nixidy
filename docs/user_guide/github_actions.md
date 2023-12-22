# GitHub Actions

Nixidy offers a GitHub Action to build and push an environment to its target branch.

## Usage

In this example it will build environments dev, test and prod on every push to main. Realistically the different environments should be built in different workflows.

```yaml
name: Generate Kubernetes manifests

on:
  push:
    branches:
      - main

jobs:
  generate:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: ["dev", "test", "prod"]
    steps:
    - uses: actions/checkout@v4

    - uses: cachix/install-nix-action@v20
      with:
        # This config is required in order to support a nixidy
        # flake repository
        extra_nix_config: |
          extra-experimental-features = nix-command flakes

    # This is optional but speeds up consecutive runs
    # by caching nix derivations between github workflows
    # runs
    - uses: DeterminateSystems/magic-nix-cache-action@v2

    # Build and push nixidy environment
    - uses: arnarg/nixidy@main
      with:
        environment: ${{matrix.env}}
```
