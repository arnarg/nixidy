import subprocess
import shutil
import sys
import json
import glob
import os
from typing import List, Optional
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


class Nixidy:
    def __init__(self, file: str, environment: str):
        """Initialize a Nixidy instance.

        Args:
            file: Path to the nix file (used when not using flakes).
            environment: Environment identifier, can be a flake reference with '#' or just environment name.
        """
        # Check if nix is in path
        nixp = shutil.which("nix")
        if nixp is None:
            raise RuntimeError("nix command not found in PATH")
        self.nix_bin = nixp

        # Get current system
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

        # Parse environment
        # Check if it's a flake
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
        """Get the attribute prefix for nix expressions.

        Returns:
            The attribute prefix string based on whether using flakes or not.
        """
        prefix = ""
        if self.is_flake:
            prefix = f"{self.flake}#nixidyEnvs.{self.system}."

        return f"{prefix}{self.environment}"

    def _cmd(self, sub_command: str, args: List[str]) -> List[str]:
        """Build a nix command with common arguments.

        Args:
            sub_command: The nix subcommand to run.
            args: Additional arguments for the command.

        Returns:
            The complete command as a list of strings.
        """
        cmd = [
            sub_command,
            "--extra-experimental-features",
            "nix-command",
        ]

        if not self.is_flake:
            cmd += ["--file", self.file]

        return cmd + args

    def run(
        self, command: List[str], check: bool = True
    ) -> subprocess.CompletedProcess:
        """Run a nix command.

        Args:
            command: The nix command arguments as a list of strings.
            check: Whether to raise an exception if the command fails.

        Returns:
            The completed process result.
        """
        cmd = [self.nix_bin] + command
        try:
            res = subprocess.run(
                cmd,
                check=check,
                stdout=subprocess.PIPE,
                stderr=sys.stderr,
            )
        except subprocess.CalledProcessError as e:
            raise NixCommandException(e, e.returncode)

        return res

    def info(self) -> NixidyEnvironmentInfo:
        """Get environment information.

        Returns:
            NixidyEnvironmentInfo containing repository and branch information.
        """
        attr = f"{self._attr_prefix}.meta"
        res = self.run(self._cmd("eval", [attr, "--json"]))

        return NixidyEnvironmentInfo.from_str(res.stdout.decode("utf-8"))

    def _build_package(
        self,
        package: str,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        """Build a specific package from the environment.

        Args:
            package: The package attribute to build.
            no_link: Whether to skip creating symlinks in the store.
            out_link: Custom output link path.
            print_paths: Whether to print output paths.

        Returns:
            The build output as a string.
        """
        attr = f"{self._attr_prefix}.{package}"
        args = [attr]

        if no_link:
            args += ["--no-link"]

        if out_link:
            args += ["--out-link", out_link]

        if print_paths:
            args += ["--print-out-paths"]

        res = self.run(self._cmd("build", args))

        return res.stdout.decode("utf-8").strip()

    def build(
        self,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        """Build the environment package.

        Args:
            no_link: Whether to skip creating symlinks in the store.
            out_link: Custom output link path.
            print_paths: Whether to print output paths.

        Returns:
            The build output as a string.
        """
        return self._build_package("environmentPackage", no_link, out_link, print_paths)

    def switch(self) -> None:
        """Build and switch to the environment.

        This method builds the activation package and runs the activate script.
        It doesn't return anything as it directly executes the activation process.
        """
        # Build the activation package
        activation_path = self._build_package(
            "activationPackage", no_link=True, print_paths=True
        )

        # Run the activate script
        activate_cmd = [f"{activation_path}/activate"]
        subprocess.run(
            activate_cmd,
            check=True,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )

    def bootstrap(self) -> str:
        """Output a manifest to bootstrap appOfApps.

        Returns:
            The bootstrap manifests as a string.
        """
        # Build the bootstrap package
        bootstrap_path = self._build_package(
            "bootstrapPackage", no_link=True, print_paths=True
        )

        # Collect all YAML manifests
        manifests_dir = bootstrap_path
        result = []

        # Using shell glob to find yaml files
        yaml_files = glob.glob(os.path.join(manifests_dir, "*.yaml"))
        for manifest in yaml_files:
            with open(manifest, "r") as f:
                result.append("---")
                result.append(f.read().rstrip())

        return "\n".join(result)

    def apply(self) -> None:
        """Build and apply declarative manifests to Kubernetes.

        This method builds the declarative package and runs the apply script.
        It doesn't return anything as it directly executes the apply process.
        """
        # Build the declarative package
        declarative_path = self._build_package(
            "declarativePackage", no_link=True, print_paths=True
        )

        # Run the apply script
        apply_cmd = [f"{declarative_path}/apply"]
        subprocess.run(
            apply_cmd,
            check=True,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
