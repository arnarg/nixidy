import json
import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class NixidyConfig:
    devenv: Optional[bool] = None
    file: Optional[str] = None


def load_config(path: str = ".nixidy.json") -> NixidyConfig:
    if not os.path.exists(path):
        return NixidyConfig()
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        return NixidyConfig()
    return NixidyConfig(devenv=data.get("devenv"), file=data.get("file"))
