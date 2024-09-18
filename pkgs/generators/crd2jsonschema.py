import sys
import yaml
import json
import string

# Generate an attribute name for use in nix options.
# Example:
# Deployments   -> deployments
# NetworkPolicy -> networkPolicies
#
# We want these to be in the plural form but the
# plural form given in CRDs is always all lowercase
# while we want it to be camelCase.
#
# Usually (if not always) it's only the last word
# of the kind's PascalCase form that is pluralized.
# So we can just go through both forms until a letter
# doesn't match and at that point splice them together.
def gen_attr_name(kind, plural):
    for i, c in enumerate(kind):
        if c.lower() != plural[i].lower():
            return kind[0].lower() + kind[1:i] + plural[i:len(plural)]

    # We got through the entire string so we can just concatinate
    # the rest of the plural form on it.
    return kind[0].lower() + kind[1:len(kind)] + plural[len(kind):len(plural)]

# Kind of PascalCase.
def uppercase_first(name):
    return name[0].upper() + name[1:]

def generate_jsonschema(files):
    schema = {'definitions': {}, 'roots': []}

    for file in files:
        with open(file, 'r') as f:
            data = yaml.safe_load(f)

            if 'spec' in data:
                group = data['spec']['group']
                kind = data['spec']['names']['kind']
                plural = data['spec']['names']['plural']
                namespaced = 'scope' in data['spec'] and data['spec']['scope'] == 'Namespaced'

                for ver in data['spec']['versions']:
                    if 'deprecated' in ver and ver['deprecated'] == True:
                        continue

                    version = ver['name']
                    definitionKey = f'{group}.{version}.{kind}'
                    schema['definitions'][definitionKey] = ver['schema']['openAPIV3Schema']
                    schema['roots'].append({
                                               'ref': definitionKey,
                                               'group': group,
                                               'version': version,
                                               'kind': kind,
                                               'name': plural,
                                               'attrName': gen_attr_name(kind, plural),
                                               'description': ver['schema']['openAPIV3Schema'].get('description', ''),
                                               'namespaced': namespaced,
                                           })

    def flatten_ref(definition, key, root=True):
        if not root:
            if 'type' in definition and definition['type'] == 'object':
                if not 'properties' in definition:
                    if 'additionalProperties' in definition:
                        # The nix generator doesn't support anyOf
                        if 'anyOf' in definition['additionalProperties']:
                            definition['additionalProperties'] = definition['additionalProperties']['anyOf'][0]

                        # If additionalProperties only contains 'x-kubernetes-preserve-unknown-fields'
                        # we can just drop the `additionalProperties` entirely and the generator
                        # will generate `types.attrs` (`types.attrsOf types.any`).
                        if 'type' not in definition['additionalProperties'] and definition['additionalProperties'].get('x-kubernetes-preserve-unknown-fields', False) == True:
                            del definition['additionalProperties']

                    return definition
                else:
                    schema['definitions'][key] = flatten_ref(definition, key, True)
                    return {
                        'description': definition.get('description', ''),
                        '$ref': f"#/definitions/{key}",
                    }

            elif 'type' in definition and definition['type'] == 'array':
                definition['items'] = flatten_ref(definition['items'], key, False)
                return definition

            # If a definition contains `x-kubernetes-preserve-unknown-fields` without
            # any `type` set, we assume the `type` is `object`.
            elif 'type' not in definition and definition.get('x-kubernetes-preserve-unknown-fields', False) == True:
                definition['type'] = 'object'
                return definition

            # The nix generator doesn't support anyOf
            elif 'anyOf' in definition:
                newDef = definition['anyOf'][0]
                newDef['description'] = definition.get('description', '')
                return newDef

            else:
                return definition

        if 'properties' in definition:
            newProps = {}

            for prop, val in definition['properties'].items():
                # CRDs never have the type information for metadata and
                # as we already have this type information from kubenix's
                # generated options we create a special `$ref` with
                # '#/global' prefix that we handle specially in our code
                # generator.
                if root and prop == 'metadata':
                    newProps[prop] = {
                        'description': 'Standard object\'s metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata',
                        '$ref': '#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta',
                    }
                else:
                    newProps[prop] = flatten_ref(val, key+uppercase_first(prop), False)

            definition['properties'] = newProps

        return definition

    for root in schema['roots']:
        key = root['ref']
        schema['definitions'][key] = flatten_ref(schema['definitions'][key], key)

    return schema

if __name__ == "__main__":
    files = sys.argv[1:]
    schema = generate_jsonschema(files)
    print(json.dumps(schema, indent=2))
