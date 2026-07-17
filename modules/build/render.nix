{ lib, pkgs }:
{
  # Shell fragment writing `spec` into $out, relative to the app's output.path.
  # `path` is environment-root relative; the per-app derivation is mounted at
  # `appOutputPath` by environmentPackage's linkFarm, so we strip the prefix and
  # write the remainder — the mount re-applies it exactly once.
  renderFile =
    appOutputPath: spec:
    let
      rel = lib.removePrefix "${appOutputPath}/" spec.path;
    in
    if spec.source ? rawFile then
      ''
        echo "Writing ${rel}"
        cp ${spec.source.rawFile} "$out/${rel}"
      ''
    else if lib.length spec.source.rendered == 1 then
      ''
        echo "Writing ${rel}"
        cat <<'EOF' | ${pkgs.yq-go}/bin/yq -P > $out/${rel}
        ${builtins.toJSON (builtins.head spec.source.rendered)}
        EOF
      ''
    else
      ''
        echo "Writing ${rel}"
        cat <<'EOF' | ${pkgs.yq-go}/bin/yq '.[] | split_doc' -P > $out/${rel}
        ${builtins.toJSON spec.source.rendered}
        EOF
      '';
}
