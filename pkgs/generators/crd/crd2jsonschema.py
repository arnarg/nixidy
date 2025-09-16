import sys
import yaml
import json
import re


# Generate an attribute name for use in nix options.
# Example:
# Deployments     -> deployments
# NetworkPolicy   -> networkPolicies
# HTTPRoute       -> httpRoutes
# CiliumCIDRGroup -> ciliumCIDRGroups
#
# We want these to be in the plural form but the
# plural form given in CRDs is always all lowercase
# while we want it to be camelCase.
#
# Usually (if not always) it's only the last word
# of the kind's PascalCase form that is pluralized.
# So we can just go through both forms until a letter
# doesn't match and at that point splice them together.
#
# If an acronym is detected at the beginning, it should
# be made lowercase as a single unit.
def gen_attr_name(kind, plural, prefix):
    # Extract leading acronym, lowercasing if no prefix
    acronym_match = re.match(r"^([A-Z]+)(?=[A-Z][a-z]|$)", kind)
    acronym = acronym_match.group(1) if acronym_match else kind[0]
    head = prefix + acronym if prefix else acronym.lower()

    # Where plural diverges from kind becomes the final suffix
    diverge_index = len(kind)
    for i, (kind_char, plural_char) in enumerate(zip(kind, plural)):
        if kind_char.lower() != plural_char.lower():
            diverge_index = i
            break

    return head + kind[len(acronym) : diverge_index] + plural[diverge_index:]


# Kind of PascalCase.
def uppercase_first(name):
    return name[0].upper() + name[1:]


def generate_jsonschema(prefix, files, attr_name_overrides):
    schema = {"definitions": {}, "roots": []}

    for file in files:
        with open(file, "r") as f:
            docs = yaml.safe_load_all(f)

            for data in docs:
                if "spec" in data and "kind" in data and data["kind"] == "CustomResourceDefinition":
                    group = data["spec"]["group"]
                    kind = data["spec"]["names"]["kind"]
                    plural = data["spec"]["names"]["plural"]
                    namespaced = (
                        "scope" in data["spec"] and data["spec"]["scope"] == "Namespaced"
                    )

                    for ver in data["spec"]["versions"]:
                        if "deprecated" in ver and ver["deprecated"] is True:
                            continue

                        version = ver["name"]
                        definitionKey = f"{group}.{version}.{kind}"
                        schema["definitions"][definitionKey] = ver["schema"][
                            "openAPIV3Schema"
                        ]
                        schema["roots"].append(
                            {
                                "ref": definitionKey,
                                "group": group,
                                "version": version,
                                "kind": kind,
                                "name": plural,
                                "attrName": attr_name_overrides.get(
                                    data["metadata"]["name"],
                                    gen_attr_name(kind, plural, prefix),
                                ),
                                "description": ver["schema"]["openAPIV3Schema"].get(
                                    "description", ""
                                ),
                                "namespaced": namespaced,
                            }
                        )

    def flatten_ref(definition, key, root=True):
        if not root:
            if "type" in definition and definition["type"] == "object":
                if "properties" not in definition:
                    if "additionalProperties" in definition:
                        if "anyOf" in definition["additionalProperties"]:
                            if definition["additionalProperties"].get(
                                "x-kubernetes-int-or-string", False
                            ):
                                # Patch the definition based on the custom x-kubernetes-int-or-string
                                definition["additionalProperties"] = {
                                    "type": "string",
                                    "format": "int-or-string",
                                }
                            else:
                                # The nix generator doesn't support anyOf
                                definition["additionalProperties"] = definition[
                                    "additionalProperties"
                                ]["anyOf"][0]

                        # If additionalProperties only contains 'x-kubernetes-preserve-unknown-fields'
                        # we can just drop the `additionalProperties` entirely and the generator
                        # will generate `types.attrs` (`types.attrsOf types.any`).
                        if "type" not in definition[
                            "additionalProperties"
                        ] and definition["additionalProperties"].get(
                            "x-kubernetes-preserve-unknown-fields", False
                        ):
                            del definition["additionalProperties"]

                    return definition
                else:
                    schema["definitions"][key] = flatten_ref(definition, key, True)
                    return {
                        "description": definition.get("description", ""),
                        "$ref": f"#/definitions/{key}",
                    }

            elif "type" in definition and definition["type"] == "array":
                definition["items"] = flatten_ref(definition["items"], key, False)
                return definition

            # The nix generator doesn't support anyOf
            elif "anyOf" in definition:
                if definition.get("x-kubernetes-int-or-string", False):
                    # Patch the definition based on the custom x-kubernetes-int-or-string
                    newDef = {"type": "string", "format": "int-or-string"}
                else:
                    # The nix generator doesn't support anyOf
                    newDef = definition["anyOf"][0]
                newDef["description"] = definition.get("description", "")
                return newDef

            # Try to infer type from special kubernetes fields
            elif "type" not in definition:
                # If a definition contains `x-kubernetes-preserve-unknown-fields` without
                # any `type` set, we assume the `type` is `object`.
                if definition.get("x-kubernetes-preserve-unknown-fields", False):
                    definition["type"] = "object"
                    return definition

                # If a definition contains `x-kubernetes-int-or-string` without any `type`
                # set, we use `type: string` with `format: int-or-string`.
                if definition.get("x-kubernetes-int-or-string", False):
                    definition["type"] = "string"
                    definition["format"] = "int-or-string"
                    return definition

            else:
                return definition

        if "properties" in definition:
            newProps = {}

            for prop, val in definition["properties"].items():
                newProps[prop] = flatten_ref(val, key + uppercase_first(prop), False)

            definition["properties"] = newProps

        return definition

    for root in schema["roots"]:
        key = root["ref"]
        schema["definitions"][key] = flatten_ref(
            set_builtin_fields(schema["definitions"][key]), key
        )

    return schema


def set_builtin_fields(definition):
    definition = definition.copy()
    if "properties" not in definition:
        definition["properties"] = {}

    if "apiVersion" not in definition["properties"]:
        definition["properties"]["apiVersion"] = {
            "description": """
APIVersion defines the versioned schema of this representation of an object.
Servers should convert recognized schemas to the latest internal value, and
may reject unrecognized values.
More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
""",
            "type": "string",
        }

    if "kind" not in definition["properties"]:
        definition["properties"]["kind"] = {
            "description": """
Kind is a string value representing the REST resource this object represents.
Servers may infer this from the endpoint the client submits requests to.
Cannot be updated.
In CamelCase.
More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
""",
            "type": "string",
        }

    # CRDs never have the type information for metadata and
    # as we already have this type information from kubenix's
    # generated options we create a special `$ref` with
    # '#/global' prefix that we handle specially in our code
    # generator.
    definition["properties"]["metadata"] = {
        "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
        "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
    }

    return definition


if __name__ == "__main__":
    optionsPath = sys.argv[1]
    with open(optionsPath, "r") as f:
        options = json.load(f)

    prefix = options.get("namePrefix", "")
    files = options.get("crds", [])
    attr_name_overrides = options.get("attrNameOverrides", {})

    schema = generate_jsonschema(prefix, files, attr_name_overrides)
    print(json.dumps(schema, indent=2))
