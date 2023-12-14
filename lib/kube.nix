{
  lib,
  klib,
  ...
}: let
  mkManifest = manifest: lib.filterAttrsRecursive (_: v: v != null) manifest;
in {
  /*
  Parses a YAML document string into a list of attribute sets.

  > This is re-exported directly from [farcaller/nix-kube-generators](https://github.com/farcaller/nix-kube-generators).

  Type:
    fromYAML :: String -> [AttrSet]

  Example:
    fromYAML ''
      apiVersion: v1
      kind: Namespace
      metadata:
        name: default
      ---
      apiVersion: v1
      kind: Namespace
      metadata:
        name: kube-system
    ''
    => [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "default";
      }
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = "kube-system";
      }
    ]
  */
  fromYAML =
    # String with a yaml document.
    yaml:
      klib.fromYAML yaml;

  /*
  Create a Kubernetes namespace manifest. This will create a manifest in
  Kubernetes format so if you want to use it for application's resources
  it should be then parsed with [lib.resources.fromManifests](#libresourcesfrommanifests).

  Type:
    namespace :: String -> AttrSet -> AttrSet

  Example:
    namespace "default" {
      labels = {
        "pod-security.kubernetes.io/enforce" = "privileged";
      };
    }
    => {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "default";
        labels = {
          "pod-security.kubernetes.io/enforce" = "privileged";
        };
      };
    }
  */
  namespace =
    # Name of the namespace manifest to create.
    name: {
      # Optional annotations to add to the namespace manifest.
      # This should be an attribute set.
      annotations ? null,
      # Optional labels to add to the namespace manifest.
      # This should be an attribute set.
      labels ? null,
    }:
      mkManifest {
        apiVersion = "v1";
        kind = "Namespace";
        metadata = {
          inherit name annotations labels;
        };
      };

  /*
  Create a Kubernetes config map manifest. This will create a manifest in
  Kubernetes format so if you want to use it for application's resources
  it should be then parsed with [lib.resources.fromManifests](#libresourcesfrommanifests).

  Type:
    configMap :: String -> AttrSet -> AttrSet

  Example:
    configMap "my-config" {
      namespace = "default";
      data."data.txt" = "Hello world!";
    }
    => {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "my-config";
        namespace = "default";
      };
      data = {
        "data.txt" = "Hello world!";
      };
    }
  */
  configMap =
    # Name of the config map manifest to create.
    name: {
      # Attribute set of data to put in the config map.
      data,
      # Optional namespace to add to the config map manifest.
      namespace ? null,
      # Optional annotations to add to the namespace manifest.
      # This should be an attribute set.
      annotations ? null,
      # Optional labels to add to the namespace manifest.
      # This should be an attribute set.
      labels ? null,
    }:
      mkManifest {
        inherit data;
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          inherit name namespace annotations labels;
        };
      };

  /*
  Create a Kubernetes secret manifest. This will create a manifest in
  Kubernetes format so if you want to use it for application's resources
  it should be then parsed with [lib.resources.fromManifests](#libresourcesfrommanifests).

  !!! danger Danger
      Due to the nature of nixidy this resource will be rendered to YAML
      and stored in cleartext in git.

      Using this resource for actual secret data is discouraged.

  Type:
    configMap :: String -> AttrSet -> AttrSet

  Example:
    secret "my-secret" {
      namespace = "default";
      stringData."data.txt" = "Hello world!";
    }
    => {
      apiVersion = "v1";
      kind = "Secret";
      metadata = {
        name = "my-secret";
        namespace = "default";
      };
      stringData = {
        "data.txt" = "Hello world!";
      };
    }
  */
  secret =
    # Name of the secret manifest to create
    name: {
      # Attribute set of data to put in the config map.
      # Values should be base64 encoded.
      data ? null,
      # Attribute set of data to put in the config map.
      # Values should be in cleartext.
      stringData ? null,
      # Optional namespace to add to the config map manifest.
      namespace ? null,
      # Optional annotations to add to the namespace manifest.
      # This should be an attribute set.
      annotations ? null,
      # Optional labels to add to the namespace manifest.
      # This should be an attribute set.
      labels ? null,
    }:
      mkManifest {
        inherit data stringData;
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          inherit name namespace annotations labels;
        };
      };

  /*
  Create a Kubernetes service manifest. This will create a manifest in
  Kubernetes format so if you want to use it for application's resources
  it should be then parsed with [lib.resources.fromManifests](#libresourcesfrommanifests).

  Type:
    service :: String -> AttrSet -> AttrSet

  Example:
    service "nginx" {
      namespace = "default";
      selector.app = "nginx";
      ports.http = {
        port = 80;
      };
    }
    => {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "nginx";
        namespace = "default";
      };
      spec = {
        type = "ClusterIP"; # Default
        selector.app = "nginx";
        ports = [
          {
            name = "http";
            port = 80;
            protocol = "TCP"; # Default
          }
        ];
      };
    }
  */
  service =
    # Name of the service manifest to create.
    name: {
      # Type of service to create. Defaults to `ClusterIP`.
      type ? "ClusterIP",
      # Label selector to match pods that this service should target.
      # This should be an attribute set.
      selector,
      # Ports this service should have.
      # This should be an attribute set (see example).
      ports,
      # Optional namespace to add to the config map manifest.
      namespace ? null,
      # Optional annotations to add to the namespace manifest.
      # This should be an attribute set.
      annotations ? null,
      # Optional labels to add to the namespace manifest.
      # This should be an attribute set.
      labels ? null,
    }: let
      defaultPortData = {protocol = "TCP";};

      portList =
        lib.mapAttrsToList (
          n: v:
            defaultPortData
            // v
            // {
              name = n;
            }
        )
        ports;
    in
      mkManifest {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          inherit name namespace annotations labels;
        };
        spec = {
          inherit type selector;
          ports = portList;
        };
      };
}
