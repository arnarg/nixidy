{ lib, buildGoModule }:

buildGoModule {
  pname = "crd2jsonschema";
  version = "0.0.1";

  src = ./.;

  vendorHash = "sha256-g+yaVIx4jxpAQ/+WrGKxhVeliYx7nLQe/zsGpxV4Fn4=";

  meta = with lib; {
    description = "Convert Kubernetes CRDs to JSON Schema";
    mainProgram = "crd2jsonschema";
    license = licenses.mit;
  };
}
