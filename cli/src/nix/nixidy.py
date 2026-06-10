import subprocess
import sys
import glob
import os
from typing import Optional
from nix.builder import DevenvBuilder, NixidyBuilder


class Nixidy:
    def __init__(self, builder: NixidyBuilder):
        self.builder = builder

    @property
    def force_print_build_output(self) -> bool:
        return isinstance(self.builder, DevenvBuilder)

    def info(self):
        return self.builder.info()

    def build(
        self,
        no_link: bool = False,
        out_link: Optional[str] = None,
        print_paths: bool = False,
    ) -> str:
        return self.builder.build(no_link, out_link, print_paths)

    def switch(self) -> None:
        path = self.builder.build_package("activationPackage")
        subprocess.run(
            [f"{path}/activate"],
            check=True,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )

    def bootstrap(self) -> str:
        path = self.builder.build_package("bootstrapPackage")
        result = []
        yaml_files = glob.glob(os.path.join(path, "*.yaml"))
        for manifest in yaml_files:
            with open(manifest, "r") as f:
                result.append("---")
                result.append(f.read().rstrip())
        return "\n".join(result)

    def apply(self) -> None:
        path = self.builder.build_package("declarativePackage")
        subprocess.run(
            [f"{path}/apply"],
            check=True,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
