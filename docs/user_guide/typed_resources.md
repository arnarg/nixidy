# Typed Resource Options

[Kubenix](https://github.com/hall/kubenix/) has done a great work with generating nix options definitions from official JSON schemas and nixidy builds on top of this.

All core Kubernetes resources are imported by default in nixidy along with Argo CD's `Application` and `AppProject`. Every resource can be defined under `applications.<applicationName>.resources.<group>.<version>.<kind>` but is also offered as an alias `applications.<applicationName>.resources.<attrName>` where `<attrName>` is the plural form of the kind in camelCase.

For example:

- `resources.core.v1.Service` -> `resources.services`
- `resources."networking.k8s.io".v1.NetworkPolicy` -> `resources.networkPolicies`

The lack of availability of typed resource options only hinders the ability to define the resources in nix. Any manifests that are rendered from a Helm Chart or defined in `applications.<applicationName>.yamls` and do not have defined resource options for that group, version and kind will go straight to the output for the application and can not be patched by nixidy.

## Generating your own resource options from CRDs

Thankfully a code generator for generating resource options from CRDs is provided by nixidy (this is based heavily on kubenix's code generator).

=== "flakes"
    As an example, to generate resource options for Cilium's `CiliumNetworkPolicy` and `CiliumClusterwideNetworkPolicy` the following can be defined in `flake.nix`.

    ```nix title="flake.nix"
    {
      description = "My ArgoCD configuration with nixidy.";

      inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
      inputs.flake-utils.url = "github:numtide/flake-utils";

      inputs.nixidy = {
        url = "github:arnarg/nixidy";
        inputs.nixpkgs.follows = "nixpkgs";
      };

      outputs = {
        self,
        nixpkgs,
        flake-utils,
        nixidy,
      }: (flake-utils.lib.eachDefaultSystem (system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        packages = {
          generators.cilium = nixidy.packages.${system}.generators.fromCRD {
            name = "cilium";
            src = pkgs.fetchFromGitHub {
              owner = "cilium";
              repo = "cilium";
              rev = "v1.15.6";
              hash = "sha256-oC6pjtiS8HvqzzRQsE+2bm6JP7Y3cbupXxCKSvP6/kU=";
            };
            crds = [
              "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"
              "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml"
            ];
          };
        };
      }));
    }
    ```

    Then running `nix build .#generators.cilium` will produce a nix file that can be copied into place in your repository. After that the generated file has to be added to `nixidy.applicationImports` in your nixidy modules.

=== "flake-less"
    As an example, to generate resource options for Cilium's `CiliumNetworkPolicy` and `CiliumClusterwideNetworkPolicy` the following can be defined in `generate.nix`.

    ```nix title="generate.nix"
    let
      # With npins
      sources = import ./npins;
      # With niv
      # sources = import ./nix/sources.nix;

      # nixpkgs added with:
      #   npins: `npins add --name nixpkgs channel nixos-unstable`
      #   niv: `niv add github nixos/nixpkgs -b nixos-unstable`
      nixpkgs = sources.nixpkgs;
      pkgs = import nixpkgs {};

      # Import nixidy
      nixidy = import sources.nixidy {inherit nixpkgs;};
    in
      {
        cilium = nixidy.generators.fromCRD {
          name = "cilium";
          src = pkgs.fetchFromGitHub {
            owner = "cilium";
            repo = "cilium";
            rev = "v1.15.6";
            hash = "sha256-oC6pjtiS8HvqzzRQsE+2bm6JP7Y3cbupXxCKSvP6/kU=";
          };
          crds = [
            "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"
            "pkg/k8s/apis/cilium.io/client/crds/v2/ciliumclusterwidenetworkpolicies.yaml"
          ];
        };
      }
    ```

    Then running `nix-build generate.nix -A cilium` will produce a nix file that can be copied into place in your repository. After that the generated file has to be added to `nixidy.applicationImports` in your nixidy modules.

```nix title="env/dev.nix"
{
  nixidy.applicationImports = [
    ./generated/cilium.nix
  ];
}
```

### Resolving Naming Conflicts

Sometimes, multiple Custom Resource Definitions from different sources might define the same resource `kind`. This can lead to conflicts in the generated attribute names. For instance, if two different operators both define a CRD with the kind `Database`, they would both try to generate options for `resources.databases`.

To resolve this, the `fromCRD` function accepts a `namePrefix` argument. This prefix will be added to the generated attribute name, making it unique.

For example, if you have two operators that both provide a `Database` CRD, you can distinguish them like this:

```nix
{
  # For postgres-operator
  postgres = nixidy.generators.fromCRD {
    name = "postgres-operator";
    namePrefix = "postgres";
    # ...
  };

  # For mysql-operator
  mysql = nixidy.generators.fromCRD {
    name = "mysql-operator";
    namePrefix = "mysql";
    # ...
  };
}
```

This will generate `resources.postgresDatabases` and `resources.mysqlDatabases` respectively, avoiding any conflicts.

If the heuristics for attribute name generation still create conflicts, for example within the same chart, or if you wish to further customize the name for ergonomics, `fromCRD` also accepts an `attrNameOverrides` argument which takes precedence over all other methods.

This argument is a mapping from the CRD's name (`<plural>.<group>`) to the desired attribute name. For example:

```nix
{
  keycloak = nixidy.generators.fromCRD {
    name = "keycloak";
    src = pkgs.fetchFromGitHub {
      owner = "crossplane-contrib";
      repo = "provider-keycloak";
      ...
    };
    crds = [
      # This CRD conflicts with Kubernetes builtin Binding
      "package/crds/authenticationflow.keycloak.crossplane.io_bindings.yaml"
      # These CRDs have identical plural references
      "package/crds/group.keycloak.crossplane.io_groups.yaml"
      "package/crds/user.keycloak.crossplane.io_groups.yaml"
    ];
    namePrefix = "keycloak";
    attrNameOverrides."groups.user.keycloak.crossplane.io" = "keycloakUserGroups";
  };
}
```

will expose `keycloakBindings`, `keycloakGroups`, and `keycloakUserGroups` under an application's `resources`.
