import subprocess
import shutil
import sys
import json
from abc import ABC, abstractmethod
from typing import Optional
from dataclasses import dataclass, asdict


class NixCommandException(Exception):
    def __init__(self, message: str, returncode: int):
        super().__init__(message)
        self.returncode = returncode


@dataclass
class NixidyEnvironmentInfo:
    repository: str
    branch: str

    @classmethod
    def from_str(cls, data: str) -> "NixidyEnvironmentInfo":
        info = json.loads(data)
        return cls(**info)

    def json(self) -> str:
        return json.dumps(asdict(self))


class NixidyBuilder(ABC):
    """Abstract interface for building nixidy environments."""

    def __init__(self, environment: str):
        self.environment = environment

    @abstractmethod
    def info(self) -> NixidyEnvironmentInfo:
        """Get environment metadata (repository, branch)."""
        ...

    @abstractmethod
    def build(
        self,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        """Build the environment package.

        Returns the raw output string from the underlying build tool.
        """
        ...

    @abstractmethod
    def build_package(self, package: str) -> str:
        """Build a specific package. Returns the store path."""
        ...


class NixBuilder(NixidyBuilder):
    """Builds environments using nix (flake or legacy)."""

    def __init__(self, file: str, environment: str):
        super().__init__(environment)

        nixp = shutil.which("nix")
        if nixp is None:
            raise RuntimeError("nix command not found in PATH")
        self.nix_bin = nixp

        res = subprocess.run(
            [
                nixp,
                "--extra-experimental-features",
                "nix-command",
                "eval",
                "--expr",
                "builtins.currentSystem",
                "--raw",
                "--impure",
            ],
            capture_output=True,
            text=True,
        )
        res.check_returncode()
        self.system = res.stdout

        if "#" in environment and not environment.startswith("#"):
            flake, _, env = environment.partition("#")
            self.is_flake = True
            self.flake = flake
            self.environment = env
        else:
            self.is_flake = False
            self.environment = environment
            self.file = file

    @property
    def _attr_prefix(self) -> str:
        prefix = ""
        if self.is_flake:
            prefix = f"{self.flake}#nixidyEnvs.{self.system}."
        return f"{prefix}{self.environment}"

    def _cmd(self, sub_command: str, args: list[str]) -> list[str]:
        cmd = [
            sub_command,
            "--extra-experimental-features",
            "nix-command",
        ]
        if not self.is_flake:
            cmd += ["--file", self.file]
        return cmd + args

    def _run(self, command: list[str]) -> subprocess.CompletedProcess:
        cmd = [self.nix_bin] + command
        try:
            res = subprocess.run(
                cmd,
                check=True,
                stdout=subprocess.PIPE,
                stderr=sys.stderr,
            )
        except subprocess.CalledProcessError as e:
            raise NixCommandException(str(e), e.returncode)
        return res

    def info(self) -> NixidyEnvironmentInfo:
        attr = f"{self._attr_prefix}.meta"
        res = self._run(self._cmd("eval", [attr, "--json"]))
        return NixidyEnvironmentInfo.from_str(res.stdout.decode("utf-8"))

    def _build_package_raw(
        self,
        package: str,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        attr = f"{self._attr_prefix}.{package}"
        args = [attr]
        if no_link:
            args += ["--no-link"]
        if out_link:
            args += ["--out-link", out_link]
        if print_paths:
            args += ["--print-out-paths"]
        res = self._run(self._cmd("build", args))
        return res.stdout.decode("utf-8").strip()

    def build(
        self,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        return self._build_package_raw(
            "environmentPackage", no_link, out_link, print_paths
        )

    def build_package(self, package: str) -> str:
        return self._build_package_raw(package, no_link=True, print_paths=True)


class DevenvBuilder(NixidyBuilder):
    """Builds environments using devenv."""

    def __init__(self, environment: str):
        super().__init__(environment)

        devenvp = shutil.which("devenv")
        if devenvp is None:
            raise RuntimeError("devenv command not found in PATH")
        self.devenv_bin = devenvp

    def _attr(self, package: str) -> str:
        return f"outputs.nixidyEnvs.{self.environment}.{package}"

    def _run(self, args: list[str]) -> subprocess.CompletedProcess:
        cmd = [self.devenv_bin] + args
        try:
            res = subprocess.run(
                cmd,
                check=True,
                stdout=subprocess.PIPE,
                stderr=sys.stderr,
            )
        except subprocess.CalledProcessError as e:
            raise NixCommandException(str(e), e.returncode)
        return res

    def _parse_build_output(self, raw: str) -> str:
        """Parse devenv build JSON output. Returns the store path."""
        data = json.loads(raw)
        paths = list(data.values())
        if len(paths) != 1:
            raise RuntimeError(f"Expected single output from devenv build, got: {data}")
        return paths[0]

    def info(self) -> NixidyEnvironmentInfo:
        attr = self._attr("meta")
        res = self._run(["eval", "--quiet", attr])
        data = json.loads(res.stdout.decode("utf-8"))
        meta = data[attr]
        return NixidyEnvironmentInfo(**meta)

    def build(
        self,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        if print_paths:
            return self.build_package("environmentPackage")

        attr = self._attr("environmentPackage")
        res = self._run(["build", "--quiet", attr])
        return res.stdout.decode("utf-8").strip()

    def build_package(self, package: str) -> str:
        attr = self._attr(package)
        res = self._run(["build", "--quiet", attr])
        return self._parse_build_output(res.stdout.decode("utf-8").strip())
