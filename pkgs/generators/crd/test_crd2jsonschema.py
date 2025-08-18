import sys
import os
import unittest
from unittest.mock import mock_open, patch

sys.path.append(os.path.dirname(__file__))

from crd2jsonschema import gen_attr_name, generate_jsonschema


class TestGenAttrName(unittest.TestCase):
    def test_simple_plural(self):
        self.assertEqual(gen_attr_name("Deployment", "deployments", ""), "deployments")

    def test_camel_case_plural(self):
        self.assertEqual(
            gen_attr_name("NetworkPolicy", "networkpolicies", ""), "networkPolicies"
        )

    def test_name_prefix(self):
        self.assertEqual(
            gen_attr_name("NetworkPolicy", "networkpolicies", "cilium"),
            "ciliumNetworkPolicies",
        )

    def test_leading_acronym(self):
        self.assertEqual(gen_attr_name("HTTPRoute", "httproutes", ""), "httpRoutes")

    def test_leading_acronym_prefix(self):
        self.assertEqual(
            gen_attr_name("HTTPRoute", "httproutes", "gateway"), "gatewayHTTPRoutes"
        )


def mock_generate_jsonschema(crd_content, prefix, attr_name_overrides):
    with patch("builtins.open", mock_open(read_data=crd_content)):
        schema = generate_jsonschema(
            prefix, ["/fake/path/crd.yaml"], attr_name_overrides
        )

    return schema


class TestGenerateJsonSchema(unittest.TestCase):
    maxDiff = None

    def test_basic_schema_generation(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              type: object
              properties:
                image:
                  type: string
                replicas:
                  type: integer
            status:
              type: object
              properties:
                availableReplicas:
                  type: integer
"""
        prefix = ""
        attr_name_overrides = {}

        schema = mock_generate_jsonschema(mock_crd_content, prefix, attr_name_overrides)

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                            "type": "string",
                        },
                        "kind": {
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                        "spec": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.FooBarSpec",
                        },
                        "status": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.FooBarStatus",
                        },
                    },
                },
                "stable.example.com.v1.FooBarSpec": {
                    "type": "object",
                    "properties": {
                        "image": {"type": "string"},
                        "replicas": {"type": "integer"},
                    },
                },
                "stable.example.com.v1.FooBarStatus": {
                    "type": "object",
                    "properties": {"availableReplicas": {"type": "integer"}},
                },
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "fooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)

    def test_empty_files_list(self):
        schema = generate_jsonschema("", [], {})
        expected_schema = {"definitions": {}, "roots": []}
        self.assertEqual(schema, expected_schema)

    def test_deprecated_version_skipped(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1alpha1
      served: true
      storage: false
      deprecated: true
      schema:
        openAPIV3Schema:
          type: object
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
"""

        schema = mock_generate_jsonschema(mock_crd_content, "", {})

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                            "type": "string",
                        },
                        "kind": {
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                    },
                }
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "fooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)

    def test_attr_name_override(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
"""

        attr_name_overrides = {"foobars.stable.example.com": "customFooBars"}

        schema = mock_generate_jsonschema(mock_crd_content, "", attr_name_overrides)

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                            "type": "string",
                        },
                        "kind": {
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                    },
                }
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "customFooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)

    def test_name_prefix(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
"""

        schema = mock_generate_jsonschema(mock_crd_content, "custom", {})

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                            "type": "string",
                        },
                        "kind": {
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                    },
                }
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "customFooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)

    def test_crd_without_scope(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
"""

        schema = mock_generate_jsonschema(mock_crd_content, "", {})

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                            "type": "string",
                        },
                        "kind": {
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                    },
                }
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "fooBars",
                    "description": "",
                    "namespaced": False,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)

    def test_crd_with_array_spec_items(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: arraytest.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: ArrayTest
    plural: arraytests
    singular: arraytest
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              type: object
              properties:
                items:
                  type: array
                  items:
                    type: object
                    properties:
                      prop1:
                        type: string
                      prop2:
                        type: integer
                      prop3:
                        type: boolean
"""
        prefix = ""
        attr_name_overrides = {}

        schema = mock_generate_jsonschema(mock_crd_content, prefix, attr_name_overrides)

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.ArrayTest": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "type": "string",
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                        },
                        "kind": {
                            "type": "string",
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                        "spec": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.ArrayTestSpec",
                        },
                    },
                },
                "stable.example.com.v1.ArrayTestSpec": {
                    "type": "object",
                    "properties": {
                        "items": {
                            "type": "array",
                            "items": {
                                "description": "",
                                "$ref": "#/definitions/stable.example.com.v1.ArrayTestSpecItems",
                            },
                        },
                    },
                },
                "stable.example.com.v1.ArrayTestSpecItems": {
                    "type": "object",
                    "properties": {
                        "prop1": {"type": "string"},
                        "prop2": {"type": "integer"},
                        "prop3": {"type": "boolean"},
                    },
                },
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.ArrayTest",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "ArrayTest",
                    "name": "arraytests",
                    "attrName": "arrayTests",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }
        self.assertEqual(schema, expected_schema)

    def test_crd_with_all_variations_of_int_or_string(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            apiVersion:
              description: |-
                APIVersion defines the versioned schema of this representation of an object.
                Servers should convert recognized schemas to the latest internal value, and
                may reject unrecognized values.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources
              type: string
            kind:
              description: |-
                Kind is a string value representing the REST resource this object represents.
                Servers may infer this from the endpoint the client submits requests to.
                Cannot be updated.
                In CamelCase.
                More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
              type: string
            metadata:
              type: object
            spec:
              type: object
              properties:
                port:
                  description: Port to use
                  x-kubernetes-int-or-string: true
                targetPort:
                  anyOf:
                  - type: integer
                  - type: string
                  description: |-
                    Name or number of the target port of the `Pod` object behind the
                    Service. The port must be specified with the container's port property.
                  x-kubernetes-int-or-string: true
                networkData:
                  type: object
                  additionalProperties:
                    anyOf:
                    - type: integer
                    - type: string
                    x-kubernetes-int-or-string: true
"""
        prefix = ""
        attr_name_overrides = {}

        schema = mock_generate_jsonschema(mock_crd_content, prefix, attr_name_overrides)

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "type": "string",
                            "description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
                        },
                        "kind": {
                            "type": "string",
                            "description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                        "spec": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.FooBarSpec",
                        },
                    },
                },
                "stable.example.com.v1.FooBarSpec": {
                    "type": "object",
                    "properties": {
                        "port": {
                            "description": "Port to use",
                            "type": "string",
                            "format": "int-or-string",
                            "x-kubernetes-int-or-string": True,
                        },
                        "targetPort": {
                            "description": "Name or number of the target port of the `Pod` object behind the\nService. The port must be specified with the container's port property.",
                            "type": "string",
                            "format": "int-or-string",
                        },
                        "networkData": {
                            "type": "object",
                            "additionalProperties": {
                                "type": "string",
                                "format": "int-or-string",
                            },
                        },
                    },
                },
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "fooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }
        self.assertEqual(schema, expected_schema)

    def test_basic_without_builtins(self):
        mock_crd_content = """
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: foobars.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: FooBar
    plural: foobars
    singular: foobar
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
                replicas:
                  type: integer
            status:
              type: object
              properties:
                availableReplicas:
                  type: integer
"""
        prefix = ""
        attr_name_overrides = {}

        schema = mock_generate_jsonschema(mock_crd_content, prefix, attr_name_overrides)

        expected_schema = {
            "definitions": {
                "stable.example.com.v1.FooBar": {
                    "type": "object",
                    "properties": {
                        "apiVersion": {
                            "description": "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n",
                            "type": "string",
                        },
                        "kind": {
                            "description": "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n",
                            "type": "string",
                        },
                        "metadata": {
                            "description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
                            "$ref": "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
                        },
                        "spec": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.FooBarSpec",
                        },
                        "status": {
                            "description": "",
                            "$ref": "#/definitions/stable.example.com.v1.FooBarStatus",
                        },
                    },
                },
                "stable.example.com.v1.FooBarSpec": {
                    "type": "object",
                    "properties": {
                        "image": {"type": "string"},
                        "replicas": {"type": "integer"},
                    },
                },
                "stable.example.com.v1.FooBarStatus": {
                    "type": "object",
                    "properties": {"availableReplicas": {"type": "integer"}},
                },
            },
            "roots": [
                {
                    "ref": "stable.example.com.v1.FooBar",
                    "group": "stable.example.com",
                    "version": "v1",
                    "kind": "FooBar",
                    "name": "foobars",
                    "attrName": "fooBars",
                    "description": "",
                    "namespaced": True,
                }
            ],
        }

        self.assertEqual(schema, expected_schema)


if __name__ == "__main__":
    unittest.main()
