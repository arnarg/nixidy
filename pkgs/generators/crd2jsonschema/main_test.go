package main

import (
	"os"
	"reflect"
	"testing"
)

// TestGenAttrName tests the attribute naming logic.
func TestGenAttrName(t *testing.T) {
	tests := []struct {
		name     string
		kind     string
		plural   string
		prefix   string
		expected string
	}{
		{
			name:     "simple_plural",
			kind:     "Deployment",
			plural:   "deployments",
			prefix:   "",
			expected: "deployments",
		},
		{
			name:     "camel_case_plural",
			kind:     "NetworkPolicy",
			plural:   "networkpolicies",
			prefix:   "",
			expected: "networkPolicies",
		},
		{
			name:     "name_prefix",
			kind:     "NetworkPolicy",
			plural:   "networkpolicies",
			prefix:   "cilium",
			expected: "ciliumNetworkPolicies",
		},
		{
			name:     "leading_acronym",
			kind:     "HTTPRoute",
			plural:   "httproutes",
			prefix:   "",
			expected: "httpRoutes",
		},
		{
			name:     "leading_acronym_prefix",
			kind:     "HTTPRoute",
			plural:   "httproutes",
			prefix:   "gateway",
			expected: "gatewayHTTPRoutes",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := genAttrName(tt.kind, tt.plural, tt.prefix)
			if got != tt.expected {
				t.Errorf("genAttrName(%q, %q, %q) = %q, want %q",
					tt.kind, tt.plural, tt.prefix, got, tt.expected)
			}
		})
	}
}

// helper to run the generator with mocked file content
func mockGenerateJsonSchema(t *testing.T, crdContent string, prefix string, attrNameOverrides map[string]string) SchemaContainer {
	tmpFile, err := os.CreateTemp("", "crd-*.yaml")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(crdContent); err != nil {
		t.Fatalf("Failed to write to temp file: %v", err)
	}
	if err := tmpFile.Close(); err != nil {
		t.Fatalf("Failed to close temp file: %v", err)
	}

	gen := NewGenerator()
	gen.generate(prefix, []string{tmpFile.Name()}, attrNameOverrides)
	return gen.Schema
}

// TestGenerateJsonSchema tests the full schema generation.
func TestGenerateJsonSchema(t *testing.T) {
	t.Run("basic_schema_generation", func(t *testing.T) {
		mockCrdContent := `
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
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		expectedDefinitions := map[string]interface{}{
			"stable.example.com.v1.FooBar": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"apiVersion": map[string]interface{}{
						"description": "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources",
						"type":        "string",
					},
					"kind": map[string]interface{}{
						"description": "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds",
						"type":        "string",
					},
					"metadata": map[string]interface{}{
						"description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
						"$ref":        "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
					},
					"spec": map[string]interface{}{
						"description": "",
						"$ref":        "#/definitions/stable.example.com.v1.FooBarSpec",
					},
					"status": map[string]interface{}{
						"description": "",
						"$ref":        "#/definitions/stable.example.com.v1.FooBarStatus",
					},
				},
			},
			"stable.example.com.v1.FooBarSpec": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"image":    map[string]interface{}{"type": "string"},
					"replicas": map[string]interface{}{"type": "integer"},
				},
			},
			"stable.example.com.v1.FooBarStatus": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"availableReplicas": map[string]interface{}{"type": "integer"},
				},
			},
		}

		expectedRoots := map[string]interface{}{
			"stable.example.com.v1.FooBar": map[string]interface{}{
				"ref":         "stable.example.com.v1.FooBar",
				"group":       "stable.example.com",
				"version":     "v1",
				"kind":        "FooBar",
				"name":        "foobars",
				"attrName":    "fooBars",
				"description": "",
				"namespaced":  true,
			},
		}

		if !reflect.DeepEqual(schema.Definitions, expectedDefinitions) {
			t.Errorf("Definitions mismatch.\nGot: %+v\nWant: %+v", schema.Definitions, expectedDefinitions)
		}
		if !reflect.DeepEqual(schema.Roots, expectedRoots) {
			t.Errorf("Roots mismatch.\nGot: %+v\nWant: %+v", schema.Roots, expectedRoots)
		}
	})

	t.Run("crd_with_empty_object", func(t *testing.T) {
		// This test ensures an empty object stays inline (type: object) and is NOT extracted to a $ref.
		mockCrdContent := `
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: emptytest.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: EmptyTest
    plural: emptytests
    singular: emptytest
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
                config:
                  type: object
                  # No properties here! Should remain { "type": "object" } inline.
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		// Check spec definition
		specKey := "stable.example.com.v1.EmptyTestSpec"
		specDefInterface, ok := schema.Definitions[specKey]
		if !ok {
			t.Fatalf("Definition %s not found in schema", specKey)
		}
		specDef := specDefInterface.(map[string]interface{})

		props := specDef["properties"].(map[string]interface{})
		config := props["config"].(map[string]interface{})

		// The fix: config should be inline object, NOT a ref
		if _, ok := config["$ref"]; ok {
			t.Error("Expected empty object 'config' to remain inline, but it was extracted to a Ref")
		}
		if config["type"] != "object" {
			t.Errorf("Expected empty object 'config' to have type 'object', got %v", config["type"])
		}
	})

	t.Run("empty_files_list", func(t *testing.T) {
		gen := NewGenerator()
		gen.generate("", []string{}, nil)

		if len(gen.Schema.Definitions) != 0 || len(gen.Schema.Roots) != 0 {
			t.Errorf("Expected empty schema, got definitions: %d, roots: %d", len(gen.Schema.Definitions), len(gen.Schema.Roots))
		}
	})

	t.Run("deprecated_version_skipped", func(t *testing.T) {
		mockCrdContent := `
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
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		if _, ok := schema.Roots["stable.example.com.v1alpha1.FooBar"]; ok {
			t.Error("Expected v1alpha1 to be skipped (deprecated), but it was present")
		}
		if _, ok := schema.Roots["stable.example.com.v1.FooBar"]; !ok {
			t.Error("Expected v1 to be present, but it was missing")
		}
	})

	t.Run("attr_name_override", func(t *testing.T) {
		mockCrdContent := `
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
              type: string
            kind:
              type: string
            metadata:
              type: object
`
		overrides := map[string]string{"foobars.stable.example.com": "customFooBars"}
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", overrides)

		root, ok := schema.Roots["stable.example.com.v1.FooBar"].(map[string]interface{})
		if !ok {
			t.Fatal("Root missing")
		}
		if root["attrName"] != "customFooBars" {
			t.Errorf("Expected attrName 'customFooBars', got %v", root["attrName"])
		}
	})

	t.Run("name_prefix", func(t *testing.T) {
		mockCrdContent := `
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
              type: string
            kind:
              type: string
            metadata:
              type: object
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "custom", nil)
		root, ok := schema.Roots["stable.example.com.v1.FooBar"].(map[string]interface{})
		if !ok {
			t.Fatal("Root missing")
		}
		if root["attrName"] != "customFooBars" {
			t.Errorf("Expected attrName 'customFooBars', got %v", root["attrName"])
		}
	})

	t.Run("crd_without_scope", func(t *testing.T) {
		mockCrdContent := `
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
              type: string
            kind:
              type: string
            metadata:
              type: object
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)
		root, ok := schema.Roots["stable.example.com.v1.FooBar"].(map[string]interface{})
		if !ok {
			t.Fatal("Root missing")
		}
		if root["namespaced"] == true {
			t.Error("Expected namespaced to be false (Cluster scope implied), got true")
		}
	})

	t.Run("crd_with_array_spec_items", func(t *testing.T) {
		mockCrdContent := `
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
              type: string
            kind:
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
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		// Check recursion into items
		specKey := "stable.example.com.v1.ArrayTestSpec"
		specDefInterface, ok := schema.Definitions[specKey]
		if !ok {
			t.Fatalf("Definition %s not found in schema", specKey)
		}
		specDef := specDefInterface.(map[string]interface{})

		props := specDef["properties"].(map[string]interface{})
		items := props["items"].(map[string]interface{})

		// The items inside the array should be a ref now
		arrayItems := items["items"].(map[string]interface{})
		if _, ok := arrayItems["$ref"]; !ok {
			t.Error("Expected array items to be flattened into a ref")
		}

		itemsKey := "stable.example.com.v1.ArrayTestSpecItems"
		if _, ok := schema.Definitions[itemsKey]; !ok {
			t.Error("Expected flattened array items definition to exist")
		}
	})

	t.Run("crd_with_all_variations_of_int_or_string", func(t *testing.T) {
		mockCrdContent := `
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
              type: string
            kind:
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
                  description: Target port description
                  x-kubernetes-int-or-string: true
                networkData:
                  type: object
                  additionalProperties:
                    anyOf:
                    - type: integer
                    - type: string
                    x-kubernetes-int-or-string: true
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		specDef := schema.Definitions["stable.example.com.v1.FooBarSpec"].(map[string]interface{})
		props := specDef["properties"].(map[string]interface{})

		// Check port (simple prop with flag)
		port := props["port"].(map[string]interface{})
		if port["type"] != "string" || port["format"] != "int-or-string" {
			t.Errorf("Port: expected string/int-or-string, got %v", port)
		}

		// Check targetPort (anyOf with flag)
		targetPort := props["targetPort"].(map[string]interface{})
		if targetPort["type"] != "string" || targetPort["format"] != "int-or-string" {
			t.Errorf("TargetPort: expected string/int-or-string, got %v", targetPort)
		}

		// Check networkData (additionalProperties with flag)
		networkData := props["networkData"].(map[string]interface{})
		addProps := networkData["additionalProperties"].(map[string]interface{})
		if addProps["type"] != "string" || addProps["format"] != "int-or-string" {
			t.Errorf("NetworkData: expected string/int-or-string, got %v", addProps)
		}
	})

	t.Run("basic_without_builtins", func(t *testing.T) {
		mockCrdContent := `
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
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)
		def := schema.Definitions["stable.example.com.v1.FooBar"].(map[string]interface{})
		props := def["properties"].(map[string]interface{})

		// Check if apiVersion and kind were added
		if _, ok := props["apiVersion"]; !ok {
			t.Error("Expected apiVersion to be added")
		}
		if _, ok := props["kind"]; !ok {
			t.Error("Expected kind to be added")
		}
		// Metadata is always added
		if _, ok := props["metadata"]; !ok {
			t.Error("Expected metadata to be added")
		}
	})

	t.Run("one_manifest_multiple_crds", func(t *testing.T) {
		mockCrdContent := `
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
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: second.stable.example.com
spec:
  group: stable.example.com
  names:
    kind: Second
    plural: seconds
    singular: second
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
---
apiVersion: v1
kind: Namespace
metadata:
  name: some-namespace
`
		schema := mockGenerateJsonSchema(t, mockCrdContent, "", nil)

		if _, ok := schema.Roots["stable.example.com.v1.FooBar"]; !ok {
			t.Error("Expected FooBar CRD to be processed")
		}
		if _, ok := schema.Roots["stable.example.com.v1.Second"]; !ok {
			t.Error("Expected Second CRD to be processed")
		}
		// Total roots should be 2, ignoring Namespace
		if len(schema.Roots) != 2 {
			t.Errorf("Expected 2 roots, got %d", len(schema.Roots))
		}
	})
}
