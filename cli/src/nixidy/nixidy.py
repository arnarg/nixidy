import sys
import click
import subprocess
import os
from nix.builder import NixBuilder, DevenvBuilder, NixCommandException, ResourceRoot
from nix.nixidy import Nixidy
from typing import Optional

_devenv_warning_printed = False


def _make_nixidy(file: str, environment: str, devenv: bool) -> Nixidy:
    global _devenv_warning_printed

    auto_devenv = (
        not devenv
        and "#" not in environment
        and os.path.exists("devenv.nix")
        and not os.path.exists("flake.nix")
        and not os.path.exists(file)
    )

    if devenv or auto_devenv:
        if auto_devenv and not _devenv_warning_printed:
            click.echo(
                click.style(
                    "Auto-detected devenv.nix, using devenv mode.",
                    fg="yellow",
                ),
                err=True,
            )
            _devenv_warning_printed = True
        if "#" in environment:
            click.echo("Flake syntax (.#env) is not supported with --devenv.", err=True)
            sys.exit(1)
        builder = DevenvBuilder(environment)
    else:
        builder = NixBuilder(file, environment)
    return Nixidy(builder)


_devenv_option = click.option(
    "--devenv",
    is_flag=True,
    help="Use devenv to build environments.",
)


@click.group()
def cli():
    pass


@cli.command("info")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@click.option(
    "--json",
    "print_json",
    help="Output info in JSON format.",
    type=bool,
    is_flag=True,
)
@_devenv_option
def info(environment: str, file: str, print_json: bool, devenv: bool):
    """Get info about a nixidy environment.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Example: `.#prod` Uses a flake in the local directory whereas `prod` does not use flake but builds the `prod` environment
    """
    nix = _make_nixidy(file, environment, devenv)

    try:
        info = nix.info()
    except NixCommandException as e:
        sys.exit(e.returncode)

    if print_json:
        click.echo(info.json())
    else:
        click.echo(f"Repository: {info.repository}")
        click.echo(f"Branch:     {info.branch}")


@cli.command("build")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@click.option(
    "--no-link",
    "no_link",
    help="Don't create a result symlink.",
    type=bool,
    is_flag=True,
)
@click.option(
    "--out-link",
    "out_link",
    help="Create a custom result symlink.",
    type=str,
    metavar="PATH",
)
@click.option(
    "--print-out-paths",
    "print_paths",
    help="Print the resulting output paths.",
    type=bool,
    is_flag=True,
)
@_devenv_option
def build(
    environment: str,
    file: str,
    no_link: bool,
    out_link: Optional[str],
    print_paths: bool,
    devenv: bool,
):
    """Build a nixidy environment.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Example: `.#prod` Uses a flake in the local directory whereas `prod` does not use flake but builds the `prod` environment
    """
    nix = _make_nixidy(file, environment, devenv)

    try:
        out = nix.build(no_link, out_link, print_paths)
    except NixCommandException as e:
        sys.exit(e.returncode)

    if print_paths or nix.force_print_build_output:
        click.echo(out)


@cli.command("switch")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@_devenv_option
def switch(environment: str, file: str, devenv: bool):
    """Build and switch to a nixidy environment.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Example: `.#prod` Uses a flake in the local directory whereas `prod` does not use flake but builds the `prod` environment
    """
    nix = _make_nixidy(file, environment, devenv)

    try:
        nix.switch()
    except NixCommandException as e:
        sys.exit(e.returncode)


@cli.command("bootstrap")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@_devenv_option
def bootstrap(environment: str, file: str, devenv: bool):
    """Output a manifest to bootstrap appOfApps.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Example: `.#prod` Uses a flake in the local directory whereas `prod` does not use flake but builds the `prod` environment
    """
    nix = _make_nixidy(file, environment, devenv)

    try:
        manifests = nix.bootstrap()
    except NixCommandException as e:
        sys.exit(e.returncode)

    click.echo(manifests)


@cli.command("apply")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@_devenv_option
def apply(environment: str, file: str, devenv: bool):
    """Build and apply declarative manifests to Kubernetes.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Example: `.#prod` Uses a flake in the local directory whereas `prod` does not use flake but builds the `prod` environment
    """
    nix = _make_nixidy(file, environment, devenv)

    try:
        nix.apply()
    except NixCommandException as e:
        sys.exit(e.returncode)


@cli.command("diff")
@click.argument("environment")
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@click.option(
    "--path",
    "-p",
    help="Path to previously built environment to compare to.",
    type=str,
    metavar="PATH",
)
@click.option(
    "--env",
    "-e",
    help="Another environment to build and compare to.",
    type=str,
    metavar="ENV",
)
@_devenv_option
def diff(
    environment: str,
    file: str,
    path: Optional[str],
    env: Optional[str],
    devenv: bool,
):
    """Diff environment manifests.

    ENVIRONMENT is the environment to build and compare with either `--path` or `--env`.

    Use `--path` to compare with a previously built environment at a specific path.

    Use `--env` to build and compare with another environment.

    Examples:

        # Compare prod with staging environment.

        nixidy diff .#prod --env .#staging

        # Compare prod with previously built manifests in ./manifests/prod

        nixidy diff .#prod --path ./manifests/prod
    """
    # Check that only one of `path` or `env` is defined.
    if path and env:
        click.echo("Only one of --path or --env can be specified.")
        sys.exit(1)
    elif not path and not env:
        click.echo("Either --path or --env must be specified.")
        sys.exit(1)

    # If `path` is defined, check that it exists.
    if path:
        if not os.path.exists(path):
            click.echo(f"Path '{path}' does not exist.")
            sys.exit(1)
        a = path

    # If `env` is defined, create an instance of Nixidy and build the environment.
    elif env:
        nix_old = _make_nixidy(file, env, devenv)
        try:
            a = nix_old.build(no_link=True, print_paths=True)
        except NixCommandException as e:
            sys.exit(e.returncode)

    # Build new environment
    nix = _make_nixidy(file, environment, devenv)

    try:
        b = nix.build(no_link=True, print_paths=True)
    except NixCommandException as e:
        sys.exit(e.returncode)

    # Compare current to new env
    diff_cmd = ["diff", "--recursive", "-u", a, b]
    diff = subprocess.run(diff_cmd, check=False, capture_output=True, text=True)

    if diff.returncode == 0:
        click.echo("No changes!")
        return

    # diff-so-fancy marks files as renamed if the path doesn't match.
    # To not cause confusion we remove all instances of `a` and `b` prefixes.
    patch = diff.stdout.replace(a, ".").replace(b, ".")

    # Run diff-so-fancy
    subprocess.run(
        ["diff-so-fancy"],
        check=False,
        input=patch.encode("utf-8"),
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

    sys.exit(diff.returncode)


def _truncate(s: str, width: int) -> str:
    if len(s) <= width:
        return s
    return s[: width - 1] + "…"


def _print_roots(roots: list[ResourceRoot]):
    attr_w = max(len(r.attrName) for r in roots) + 1
    max_group = 30
    max_kind = 30
    header = (
        f"{'RESOURCE':<{attr_w}}  "
        f"{'VERSION':<10}  "
        f"{_truncate('GROUP', max_group):<{max_group}}  "
        f"{_truncate('KIND', max_kind):<{max_kind}}"
    )
    click.echo(click.style(header, bold=True))
    for r in roots:
        click.echo(
            f"{r.attrName:<{attr_w}}  "
            f"{r.version:<10}  "
            f"{_truncate(r.group, max_group):<{max_group}}  "
            f"{_truncate(r.kind, max_kind):<{max_kind}}"
        )


def _print_explain(attr_name: str, dot_path: str, data: dict):
    description = data.get("description", "")
    type_info = data.get("type", {})
    type_name = type_info.get("description", "unspecified")

    path = f"{attr_name}.{dot_path}".rstrip(".") if dot_path else attr_name
    click.echo(f"{click.style(path, bold=True)} <{type_name}>\n")

    if description:
        click.echo("DESCRIPTION:")
        click.echo(f"    {description.replace('\n', '\n    ')}\n")

    children = data.get("children", {})
    if not children:
        return

    click.echo("FIELDS:")
    for name, child in children.items():
        child_type = child.get("type", {}).get("description", "unspecified")
        child_desc = child.get("description", "")
        click.echo(f"  {name}  <{child_type}>")
        if child_desc:
            click.echo(f"    {child_desc.replace('\n', '\n    ')}")
        click.echo("\n")


@cli.command("resources")
@click.argument("environment")
@click.argument("resource_path", required=False, default=None)
@click.option(
    "--file",
    "-f",
    help="Path to entrypoint nix file (only flake-less).",
    type=str,
    default="default.nix",
    show_default=True,
    metavar="PATH",
)
@_devenv_option
def resources(environment: str, resource_path: Optional[str], file: str, devenv: bool):
    """Show information about resource types and their options.

    ENVIRONMENT is used to determine if flakes or flake-less nix should be used and which environment should be built.

    Without RESOURCE_PATH: list all available resource types.

    With RESOURCE_PATH (e.g. `deployments` or `deployments.spec`): show option details at that path.

    Examples:

        # List all resource types.

        nixidy resources .#prod

        # List type information for a specific resource.

        nixidy resources .#prod deployments.spec.template.spec
    """
    nix = _make_nixidy(file, environment, devenv)

    if resource_path is None:
        try:
            roots = nix.resources_roots()
        except NixCommandException as e:
            sys.exit(e.returncode)
        _print_roots(roots)
    else:
        attr_name, dot_path = (
            resource_path.split(".", 1) if "." in resource_path else (resource_path, "")
        )
        try:
            result = nix.explain_resource(attr_name, dot_path)
        except NixCommandException as e:
            sys.exit(e.returncode)
        if result is None:
            click.echo(
                f"Error: resource '{attr_name}' or path '{dot_path}' not found.",
                err=True,
            )
            sys.exit(1)
        _print_explain(attr_name, dot_path, result)


def main():
    cli(prog_name="nixidy")


if __name__ == "__main__":
    main()
