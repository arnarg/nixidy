{
  runCommand,
  lib,
  bash,
  coreutils,
  findutils,
  jq,
}:
runCommand "nixidy" {
  preferLocalBuild = true;
} ''
  install -v -D -m755  ${./nixidy} $out/bin/nixidy

  substituteInPlace $out/bin/nixidy \
    --subst-var-by bash "${bash}" \
    --subst-var-by DEP_PATH "${
    lib.makeBinPath [
      coreutils
      findutils
      jq
    ]
  }"
''
