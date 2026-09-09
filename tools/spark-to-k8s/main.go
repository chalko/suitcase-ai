package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

func main() {
	var (
		inputPath  string
		outputPath string
		namespace  string
		validate   bool
	)

	flag.StringVar(&inputPath, "input", "", "Path to the input SparkRecipe YAML file (shorthand: -i)")
	flag.StringVar(&inputPath, "i", "", "Path to the input SparkRecipe YAML file")
	flag.StringVar(&outputPath, "output", "", "Path to the output Kubernetes YAML manifest file (shorthand: -o)")
	flag.StringVar(&outputPath, "o", "", "Path to the output Kubernetes YAML manifest file")
	flag.StringVar(&namespace, "namespace", "nim-system", "Kubernetes namespace for the generated resources (shorthand: -n)")
	flag.StringVar(&namespace, "n", "nim-system", "Kubernetes namespace for the generated resources")
	flag.BoolVar(&validate, "validate", false, "Validate recipe syntax and constraints without generating full manifest (shorthand: -v)")
	flag.BoolVar(&validate, "v", false, "Validate recipe syntax and constraints without generating full manifest")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: spark-to-k8s [options] <recipe.yaml>\n\n")
		fmt.Fprintf(os.Stderr, "Compiles declarative SparkRecipe specifications into validated Kubernetes Deployment and Service manifests.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  spark-to-k8s -i recipes/nemotron-49b-fp8.yaml -o manifests/nemotron-49b.yaml\n")
		fmt.Fprintf(os.Stderr, "  spark-to-k8s --validate recipes/north-mini-code-nvfp4.yaml\n")
		fmt.Fprintf(os.Stderr, "  spark-to-k8s recipes/north-mini-code-nvfp4.yaml > north-mini-code-nvfp4.yaml\n")
	}

	flag.Parse()

	// If inputPath is not set via flag, check positional arguments
	if inputPath == "" {
		if flag.NArg() > 0 {
			inputPath = flag.Arg(0)
		} else {
			flag.Usage()
			os.Exit(1)
		}
	}

	// Read recipe file
	data, err := os.ReadFile(inputPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to read input file %q: %v\n", inputPath, err)
		os.Exit(1)
	}

	var recipe SparkRecipe
	if err := yaml.Unmarshal(data, &recipe); err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to parse SparkRecipe YAML: %v\n", err)
		os.Exit(1)
	}

	// Validate recipe
	if err := ValidateRecipe(&recipe); err != nil {
		fmt.Fprintf(os.Stderr, "Validation Error in %q: %v\n", inputPath, err)
		os.Exit(1)
	}

	if validate {
		fmt.Printf("✓ Recipe %q (%s / %s) is valid.\n", recipe.Metadata.Name, recipe.Spec.Runtime.Engine, recipe.Spec.Hardware.Accelerator)
		return
	}

	// Compile recipe to Kubernetes manifests
	manifestYAML, err := Compile(&recipe, CompilerOptions{
		Namespace: namespace,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Compilation Error: %v\n", err)
		os.Exit(1)
	}

	// Write to output file or stdout
	if outputPath != "" {
		outDir := filepath.Dir(outputPath)
		if outDir != "." && outDir != "" {
			if err := os.MkdirAll(outDir, 0755); err != nil {
				fmt.Fprintf(os.Stderr, "Error: failed to create output directory %q: %v\n", outDir, err)
				os.Exit(1)
			}
		}
		if err := os.WriteFile(outputPath, []byte(manifestYAML), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to write output manifest to %q: %v\n", outputPath, err)
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "✓ Generated Kubernetes manifest: %s\n", outputPath)
	} else {
		// Print to stdout
		fmt.Print(manifestYAML)
	}
}
