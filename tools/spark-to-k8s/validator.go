package main

import (
	"fmt"
	"strings"
)

// ValidateRecipe performs schema, UMA envelope, hardware, and storage validation on a SparkRecipe.
func ValidateRecipe(recipe *SparkRecipe) error {
	if recipe == nil {
		return fmt.Errorf("recipe cannot be nil")
	}

	// 1. API Version & Kind Validation
	if recipe.APIVersion != "inference.colt.ai/v1alpha1" {
		return fmt.Errorf("unsupported apiVersion %q; must be 'inference.colt.ai/v1alpha1'", recipe.APIVersion)
	}
	if recipe.Kind != "SparkRecipe" {
		return fmt.Errorf("unsupported kind %q; must be 'SparkRecipe'", recipe.Kind)
	}

	// 2. Metadata Validation
	if strings.TrimSpace(recipe.Metadata.Name) == "" {
		return fmt.Errorf("metadata.name is required")
	}

	// 3. Model Spec Validation
	if strings.TrimSpace(recipe.Spec.Model.ID) == "" {
		return fmt.Errorf("spec.model.id is required")
	}

	// 4. Runtime & UMA Memory Envelope Validation
	engine := strings.ToLower(strings.TrimSpace(recipe.Spec.Runtime.Engine))
	if engine != "nim" && engine != "vllm" {
		return fmt.Errorf("spec.runtime.engine must be 'nim' or 'vllm', got %q", recipe.Spec.Runtime.Engine)
	}

	if strings.TrimSpace(recipe.Spec.Runtime.Image) == "" {
		return fmt.Errorf("spec.runtime.image is required")
	}

	// UMA memory envelope: On GB10 unified memory architecture (128GB LPDDR5X),
	// gpuMemoryUtilization must not exceed 0.75 (96GB) to preserve a 32GB host RAM buffer.
	if recipe.Spec.Runtime.GPUMemoryUtilization <= 0 {
		return fmt.Errorf("spec.runtime.gpuMemoryUtilization must be greater than 0")
	}
	if recipe.Spec.Runtime.GPUMemoryUtilization > 0.75 {
		return fmt.Errorf("spec.runtime.gpuMemoryUtilization (%.2f) exceeds UMA envelope maximum of 0.75 (96 GB)", recipe.Spec.Runtime.GPUMemoryUtilization)
	}

	if recipe.Spec.Runtime.MaxNumSeqs < 0 {
		return fmt.Errorf("spec.runtime.maxNumSeqs must be non-negative")
	}
	if recipe.Spec.Runtime.MaxModelLen < 0 {
		return fmt.Errorf("spec.runtime.maxModelLen must be non-negative")
	}

	// Engine specific checks
	if engine == "nim" {
		// Profile is recommended or required for NIM
	}

	// 5. Hardware Capabilities Validation
	accel := strings.ToLower(strings.TrimSpace(recipe.Spec.Hardware.Accelerator))
	if accel != "gb10" {
		return fmt.Errorf("spec.hardware.accelerator must be 'gb10', got %q", recipe.Spec.Hardware.Accelerator)
	}

	arch := strings.ToLower(strings.TrimSpace(recipe.Spec.Hardware.Arch))
	if arch != "arm64" {
		return fmt.Errorf("spec.hardware.arch must be 'arm64', got %q", recipe.Spec.Hardware.Arch)
	}

	if recipe.Spec.Hardware.GPUCount < 1 {
		return fmt.Errorf("spec.hardware.gpuCount must be at least 1, got %d", recipe.Spec.Hardware.GPUCount)
	}

	// 6. Storage Validation (ModelDepot & ReadyLocker paths)
	depotSrc := strings.TrimSpace(recipe.Spec.Storage.DepotSource)
	if !strings.HasPrefix(depotSrc, "/mnt/model-depot") {
		return fmt.Errorf("spec.storage.depotSource must be rooted in ModelDepot (/mnt/model-depot), got %q", depotSrc)
	}

	readyTarget := strings.TrimSpace(recipe.Spec.Storage.ReadyTarget)
	if readyTarget == "" {
		return fmt.Errorf("spec.storage.readyTarget is required")
	}
	if !strings.HasPrefix(readyTarget, "/opt/nim/.cache") && !strings.HasPrefix(readyTarget, "/workspace/models/fast-cache") {
		return fmt.Errorf("spec.storage.readyTarget must be rooted in fast cache (/opt/nim/.cache), got %q", readyTarget)
	}

	return nil
}
