# GitHub Actions

Nixidy offers two GitHub Actions to build and switch to an environment.

## arnarg/nixidy/actions/build

This action will run `nixidy build` on a specified environment. It will not produce a `result` symlink and instead will have the output path in it's output `out-path`.

### Example

```yaml
name: Generate Kubernetes manifests

on:
  push:
    branches:
      - main
    paths-ignore:
      - manifests/**

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: cachix/install-nix-action@v31
      with:
        # The `arnarg/nixidy/actions/build` action depends
        # on nix flakes to run the actual nixidy cli.
        # Therefore the following setting is required even
        # when using nixidy with non-flakes.
        extra_nix_config: |
          extra-experimental-features = nix-command flakes

    - uses: arnarg/nixidy/actions/build@main
      id: build
      with:
        environment: .#dev
        # Without flakes:
        # environment: dev

    - shell: bash
      run: |
        rsync --recursive --delete '${{steps.build.outputs.out-path}}/' manifests

    - uses: EndBug/add-and-commit@v9
      id: commit
      with:
        default_author: github_actions
        message: "chore: promote to dev ${{github.sha}}"
        fetch: false
        new_branch: promote/env/dev
        push: --set-upstream origin promote/env/dev --force

    - uses: thomaseizinger/create-pull-request@1.4.0
      if: ${{ steps.commit.outputs.pushed == 'true' }}
      with:
        github_token: ${{github.token}}
        head: promote/env/dev
        base: main
        title: "chore: promote to dev ${{github.sha}}"
```

## arnarg/nixidy/actions/switch

This action will run `nixidy switch` on a specified environment.

### Example

```yaml
name: Generate Kubernetes manifests

on:
  push:
    branches:
      - main
    paths-ignore:
      - manifests/**

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: cachix/install-nix-action@v31
      with:
        # The `arnarg/nixidy/actions/switch` action depends
        # on nix flakes to run the actual nixidy cli.
        # Therefore the following setting is required even
        # when using nixidy with non-flakes.
        extra_nix_config: |
          extra-experimental-features = nix-command flakes

    - uses: arnarg/nixidy/actions/switch@main
      with:
        environment: .#dev
        # Without flakes:
        # environment: dev

    - uses: EndBug/add-and-commit@v9
      id: commit
      with:
        default_author: github_actions
        message: "chore: promote to dev ${{github.sha}}"
        fetch: false
        new_branch: promote/env/dev
        push: --set-upstream origin promote/env/dev --force

    - uses: thomaseizinger/create-pull-request@1.4.0
      if: ${{ steps.commit.outputs.pushed == 'true' }}
      with:
        github_token: ${{github.token}}
        head: promote/env/dev
        base: main
        title: "chore: promote to dev ${{github.sha}}"
```
