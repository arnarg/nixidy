import sys
import yaml
import json
import string

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
                                               'attrName': plural,
                                               'description': ver['schema']['openAPIV3Schema']['description'],
                                               'namespaced': namespaced,
                                           })

    def flatten_ref(definition, key, root=True):
        if not root:
            if 'type' in definition and definition['type'] == 'object':
                if not 'properties' in definition:
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

            elif 'anyOf' in definition:
                newDef = definition['anyOf'][0]
                newDef['description'] = definition.get('description', '')
                return newDef

            else:
                return definition

        if 'properties' in definition:
            newProps = {}

            for prop, val in definition['properties'].items():
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
