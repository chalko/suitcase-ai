package main

import (
	"bytes"
	"embed"
	"fmt"
	"path/filepath"
	"strings"
	"text/template"
)

//go:embed templates/*.tmpl
var templateFS embed.FS

// CompilerOptions holds configuration options for compilation.
type CompilerOptions struct {
	Namespace string
}

// TemplateData models parameters passed to the manifest templates.
type TemplateData struct {
	Name                 string
	Namespace            string
	Engine               string
	ModelID              string
	Image                string
	Profile              string
	GPUMemoryUtilization string
	MaxModelLen          int
	MaxNumSeqs           int
	PassthroughArgs      string
	PassthroughArgsList  []string
	GPUCount             int
	DepotSource          string
	ReadyTarget          string
	DepotParentDir       string
}

// Compile translates a SparkRecipe into multi-document Kubernetes YAML manifests (Deployment + Service).
func Compile(recipe *SparkRecipe, opts CompilerOptions) (string, error) {
	if err := ValidateRecipe(recipe); err != nil {
		return "", fmt.Errorf("recipe validation failed: %w", err)
	}

	namespace := opts.Namespace
	if strings.TrimSpace(namespace) == "" {
		namespace = "nim-system"
	}

	tmpl, err := template.ParseFS(templateFS, "templates/model.yaml.tmpl")
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	gpuCount := recipe.Spec.Hardware.GPUCount
	if gpuCount <= 0 {
		gpuCount = 1
	}

	var passthroughArgsList []string
	if strings.TrimSpace(recipe.Spec.Runtime.PassthroughArgs) != "" {
		passthroughArgsList = strings.Fields(recipe.Spec.Runtime.PassthroughArgs)
	}

	data := TemplateData{
		Name:                 recipe.Metadata.Name,
		Namespace:            namespace,
		Engine:               strings.ToLower(strings.TrimSpace(recipe.Spec.Runtime.Engine)),
		ModelID:              recipe.Spec.Model.ID,
		Image:                recipe.Spec.Runtime.Image,
		Profile:              recipe.Spec.Runtime.Profile,
		GPUMemoryUtilization: fmt.Sprintf("%.2f", recipe.Spec.Runtime.GPUMemoryUtilization),
		MaxModelLen:          recipe.Spec.Runtime.MaxModelLen,
		MaxNumSeqs:           recipe.Spec.Runtime.MaxNumSeqs,
		PassthroughArgs:      recipe.Spec.Runtime.PassthroughArgs,
		PassthroughArgsList:  passthroughArgsList,
		GPUCount:             gpuCount,
		DepotSource:          recipe.Spec.Storage.DepotSource,
		ReadyTarget:          recipe.Spec.Storage.ReadyTarget,
		DepotParentDir:       filepath.Dir(recipe.Spec.Storage.ReadyTarget),
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return "", fmt.Errorf("failed to render manifest template: %w", err)
	}

	return buf.String(), nil
}
