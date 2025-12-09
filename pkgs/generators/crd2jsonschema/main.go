package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"unicode"

	"gopkg.in/yaml.v3"
)

// Options represents the structure of the input JSON options file.
type Options struct {
	NamePrefix        string            `json:"namePrefix"`
	CRDs              []string          `json:"crds"`
	AttrNameOverrides map[string]string `json:"attrNameOverrides"`
}

// SchemaContainer holds the final JSON schema structure.
type SchemaContainer struct {
	Definitions map[string]interface{} `json:"definitions"`
	Roots       map[string]interface{} `json:"roots"`
}

// Generator manages the state of the schema generation.
type Generator struct {
	Schema SchemaContainer
}

func NewGenerator() *Generator {
	return &Generator{
		Schema: SchemaContainer{
			Definitions: make(map[string]interface{}),
			Roots:       make(map[string]interface{}),
		},
	}
}

// uppercaseFirst capitalizes the first character of a string.
func uppercaseFirst(s string) string {
	if s == "" {
		return ""
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

// genAttrName generates a camelCase attribute name from PascalCase Kind and lowercase plural.
func genAttrName(kind, plural, prefix string) string {
	runes := []rune(kind)

	// 1. Identify Acronym length
	end := 0
	for end < len(runes) && unicode.IsUpper(runes[end]) {
		end++
	}

	acronymLen := end
	if end < len(runes) && end > 1 {
		acronymLen--
	}

	acronym := ""
	if acronymLen > 0 {
		acronym = string(runes[:acronymLen])
	} else if len(runes) > 0 {
		acronym = string(runes[0])
	}

	var head string
	if prefix != "" {
		head = prefix + acronym
	} else {
		head = strings.ToLower(acronym)
	}

	// 2. Find where plural diverges from kind
	divergeIndex := len(kind)
	kRunes := []rune(kind)
	pRunes := []rune(plural)

	minLen := len(kRunes)
	if len(pRunes) < minLen {
		minLen = len(pRunes)
	}

	for i := 0; i < minLen; i++ {
		if unicode.ToLower(kRunes[i]) != unicode.ToLower(pRunes[i]) {
			divergeIndex = i
			break
		}
	}

	suffix := ""
	if divergeIndex < len(pRunes) {
		suffix = string(pRunes[divergeIndex:])
	}

	// 3. Construct the middle part
	mid := ""
	startIndex := len([]rune(acronym))

	if startIndex < divergeIndex && startIndex < len(kRunes) {
		endIndex := divergeIndex
		if endIndex > len(kRunes) {
			endIndex = len(kRunes)
		}
		mid = string(kRunes[startIndex:endIndex])
	}

	return head + mid + suffix
}

// deepCopy creates a deep copy of a generic map/interface structure.
func deepCopy(src interface{}) interface{} {
	if src == nil {
		return nil
	}
	switch v := src.(type) {
	case map[string]interface{}:
		dst := make(map[string]interface{})
		for key, value := range v {
			dst[key] = deepCopy(value)
		}
		return dst
	case []interface{}:
		dst := make([]interface{}, len(v))
		for i, value := range v {
			dst[i] = deepCopy(value)
		}
		return dst
	default:
		return src
	}
}

// setBuiltinFields ensures apiVersion, kind, and metadata exist.
func setBuiltinFields(definition map[string]interface{}) map[string]interface{} {
	def := deepCopy(definition).(map[string]interface{})

	props, ok := def["properties"].(map[string]interface{})
	if !ok {
		props = make(map[string]interface{})
		def["properties"] = props
	}

	if _, exists := props["apiVersion"]; !exists {
		props["apiVersion"] = map[string]interface{}{
			"description": "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n",
			"type":        "string",
		}
	}

	if _, exists := props["kind"]; !exists {
		props["kind"] = map[string]interface{}{
			"description": "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n",
			"type":        "string",
		}
	}

	props["metadata"] = map[string]interface{}{
		"description": "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata",
		"$ref":        "#/global/io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta",
	}

	return def
}

// flattenRef processes the schema recursively.
func (g *Generator) flattenRef(definition map[string]interface{}, key string, root bool) map[string]interface{} {
	if !root {
		typ, hasType := definition["type"].(string)

		if hasType && typ == "object" {
			// Case: Object without explicit properties (Map/Dict)
			// In Python, this was: if "properties" not in definition: return definition
			if _, hasProps := definition["properties"]; !hasProps {

				if additionalProps, ok := definition["additionalProperties"].(map[string]interface{}); ok {

					// Handle anyOf in additionalProperties
					if anyOf, ok := additionalProps["anyOf"].([]interface{}); ok && len(anyOf) > 0 {
						if isIntOrString, _ := additionalProps["x-kubernetes-int-or-string"].(bool); isIntOrString {
							definition["additionalProperties"] = map[string]interface{}{
								"type":   "string",
								"format": "int-or-string",
							}
						} else {
							definition["additionalProperties"] = anyOf[0]
						}
					}

					// Handle x-kubernetes-preserve-unknown-fields
					if _, hasTypeInAdd := additionalProps["type"]; !hasTypeInAdd {
						if preserve, _ := additionalProps["x-kubernetes-preserve-unknown-fields"].(bool); preserve {
							delete(definition, "additionalProperties")
						}
					}

					return definition
				}

				// CHANGE: If there are no properties and no additionalProperties to process,
				// we return the definition inline. We do NOT extract it to a ref.
				// This ensures that empty objects are rendered as `type = types.attrs` downstream.
				return definition

			} else {
				// Case: Object WITH properties.
				// These MUST be extracted to a separate definition so they become submodules.
				g.Schema.Definitions[key] = g.flattenRef(definition, key, true)

				desc, _ := definition["description"].(string)
				return map[string]interface{}{
					"description": desc,
					"$ref":        fmt.Sprintf("#/definitions/%s", key),
				}
			}

		} else if hasType && typ == "array" {
			if items, ok := definition["items"].(map[string]interface{}); ok {
				definition["items"] = g.flattenRef(items, key, false)
			}
			return definition

		} else if _, hasAnyOf := definition["anyOf"]; hasAnyOf {
			var newDef map[string]interface{}

			if isIntOrString, _ := definition["x-kubernetes-int-or-string"].(bool); isIntOrString {
				newDef = map[string]interface{}{
					"type":   "string",
					"format": "int-or-string",
				}
			} else {
				anyOfList := definition["anyOf"].([]interface{})
				if len(anyOfList) > 0 {
					if first, ok := anyOfList[0].(map[string]interface{}); ok {
						newDef = deepCopy(first).(map[string]interface{})
					} else {
						newDef = make(map[string]interface{})
					}
				}
			}

			if desc, ok := definition["description"].(string); ok {
				newDef["description"] = desc
			}
			return newDef

		} else if !hasType {
			if preserve, _ := definition["x-kubernetes-preserve-unknown-fields"].(bool); preserve {
				definition["type"] = "object"
				return definition
			}

			if isIntOrString, _ := definition["x-kubernetes-int-or-string"].(bool); isIntOrString {
				definition["type"] = "string"
				definition["format"] = "int-or-string"
				return definition
			}

			return definition
		}
	}

	// Recursively flatten properties
	if props, ok := definition["properties"].(map[string]interface{}); ok {
		newProps := make(map[string]interface{})
		for propName, propVal := range props {
			if propMap, ok := propVal.(map[string]interface{}); ok {
				newProps[propName] = g.flattenRef(propMap, key+uppercaseFirst(propName), false)
			} else {
				newProps[propName] = propVal
			}
		}
		definition["properties"] = newProps
	}

	return definition
}

func (g *Generator) generate(prefix string, files []string, attrNameOverrides map[string]string) {
	for _, file := range files {
		f, err := os.Open(file)
		if err != nil {
			log.Printf("Failed to open file %s: %v", file, err)
			continue
		}

		decoder := yaml.NewDecoder(f)

		for {
			var data map[string]interface{}
			err := decoder.Decode(&data)
			if err == io.EOF {
				break
			}
			if err != nil {
				log.Printf("Error decoding YAML in %s: %v", file, err)
				break
			}

			kind, _ := data["kind"].(string)
			if kind != "CustomResourceDefinition" {
				continue
			}

			spec, _ := data["spec"].(map[string]interface{})
			group, _ := spec["group"].(string)
			names, _ := spec["names"].(map[string]interface{})
			crdKind, _ := names["kind"].(string)
			plural, _ := names["plural"].(string)
			scope, _ := spec["scope"].(string)
			namespaced := scope == "Namespaced"

			versions, _ := spec["versions"].([]interface{})

			for _, ver := range versions {
				vMap, ok := ver.(map[string]interface{})
				if !ok {
					continue
				}

				if deprecated, ok := vMap["deprecated"].(bool); ok && deprecated {
					continue
				}

				versionName, _ := vMap["name"].(string)
				definitionKey := fmt.Sprintf("%s.%s.%s", group, versionName, crdKind)

				schema, _ := vMap["schema"].(map[string]interface{})
				openAPIV3Schema, _ := schema["openAPIV3Schema"].(map[string]interface{})

				g.Schema.Definitions[definitionKey] = openAPIV3Schema

				metadata, _ := data["metadata"].(map[string]interface{})
				metaName, _ := metadata["name"].(string)

				attrName := ""
				if override, ok := attrNameOverrides[metaName]; ok {
					attrName = override
				} else {
					attrName = genAttrName(crdKind, plural, prefix)
				}

				desc, _ := openAPIV3Schema["description"].(string)

				g.Schema.Roots[definitionKey] = map[string]interface{}{
					"ref":         definitionKey,
					"group":       group,
					"version":     versionName,
					"kind":        crdKind,
					"name":        plural,
					"attrName":    attrName,
					"description": desc,
					"namespaced":  namespaced,
				}
			}
		}
		f.Close()
	}

	for _, rootVal := range g.Schema.Roots {
		root := rootVal.(map[string]interface{})
		key := root["ref"].(string)

		if def, ok := g.Schema.Definitions[key].(map[string]interface{}); ok {
			withBuiltins := setBuiltinFields(def)
			g.Schema.Definitions[key] = g.flattenRef(withBuiltins, key, true)
		}
	}
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: go run main.go <options-file>")
	}

	optionsPath := os.Args[1]
	optData, err := os.ReadFile(optionsPath)
	if err != nil {
		log.Fatalf("Failed to read options file: %v", err)
	}

	var options Options
	if err := json.Unmarshal(optData, &options); err != nil {
		log.Fatalf("Failed to parse options JSON: %v", err)
	}

	gen := NewGenerator()
	gen.generate(options.NamePrefix, options.CRDs, options.AttrNameOverrides)

	output, err := json.MarshalIndent(gen.Schema, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal schema: %v", err)
	}

	fmt.Println(string(output))
}
