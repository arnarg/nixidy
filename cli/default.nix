{
  lib,
  python3Packages,
  makeWrapper,
  diffutils,
  diff-so-fancy,
}:
let
  pyproject = lib.importTOML ./pyproject.toml;
in
python3Packages.buildPythonApplication {
  pname = "nixidy";
  version = pyproject.project.version;
  pyproject = true;

  src = ./.;

  build-system = with python3Packages; [
    setuptools
  ];

  dependencies = with python3Packages; [
    click
  ];

  nativeBuildInputs = [
    makeWrapper
  ];

  postInstall = ''
    wrapProgram $out/bin/nixidy \
      --prefix PATH : ${
        lib.makeBinPath [
          diffutils
          diff-so-fancy
        ]
      }
  '';
}
