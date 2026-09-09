package main

import (
	"os"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func loadRecipeFile(t *testing.T, path string) *SparkRecipe {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read recipe file %s: %v", path, err)
	}
	var recipe SparkRecipe
	if err := yaml.Unmarshal(data, &recipe); err != nil {
		t.Fatalf("failed to unmarshal recipe %s: %v", path, err)
	}
	return &recipe
}

func TestCompile_NIMRecipe(t *testing.T) {
	recipePath := "../../provision/k8s/apps/inference/recipes/nemotron-49b-fp8.yaml"
	recipe := loadRecipeFile(t, recipePath)

	out, err := Compile(recipe, CompilerOptions{Namespace: "nim-system"})
	if err != nil {
		t.Fatalf("unexpected error compiling NIM recipe: %v", err)
	}

	// 1. Verify Deployment & Service structure
	if !strings.Contains(out, "kind: Deployment") {
		t.Errorf("expected output to contain kind: Deployment")
	}
	if !strings.Contains(out, "kind: Service") {
		t.Errorf("expected output to contain kind: Service")
	}

	// 2. Verify 3-phase initContainer pattern
	if !strings.Contains(out, "name: depot-hydration-preflight") {
		t.Errorf("missing Phase 1A depot-hydration-preflight container")
	}
	if !strings.Contains(out, "name: download-model") {
		t.Errorf("missing Phase 1B download-model container for NIM")
	}
	if !strings.Contains(out, "name: cache-flusher") {
		t.Errorf("missing Phase 1C cache-flusher container")
	}

	// 3. Verify UMA page cache flush logic
	if !strings.Contains(out, "echo 3 > /proc/sys/vm/drop_caches") {
		t.Errorf("missing /proc/sys/vm/drop_caches flush in cache-flusher")
	}
	if !strings.Contains(out, "privileged: true") {
		t.Errorf("cache-flusher must be privileged")
	}

	// 4. Verify GB10 nodeSelector and tolerations
	if !strings.Contains(out, "accelerator: gb10") {
		t.Errorf("missing accelerator: gb10 nodeSelector")
	}
	if !strings.Contains(out, "kubernetes.io/arch: arm64") {
		t.Errorf("missing kubernetes.io/arch: arm64 nodeSelector")
	}
	if !strings.Contains(out, "nvidia.com/gpu.present: \"true\"") {
		t.Errorf("missing nvidia.com/gpu.present: \"true\" nodeSelector")
	}
	if !strings.Contains(out, "runtimeClassName: nvidia") {
		t.Errorf("missing runtimeClassName: nvidia")
	}
	if !strings.Contains(out, "hostNetwork: true") {
		t.Errorf("missing hostNetwork: true")
	}

	// 5. Verify imagePullSecrets for NIM
	if !strings.Contains(out, "name: ngc-imagepull-secret") {
		t.Errorf("missing ngc-imagepull-secret for NIM")
	}

	// 6. Verify Service ports
	if !strings.Contains(out, "port: 8000") || !strings.Contains(out, "port: 8002") {
		t.Errorf("Service must expose ports 8000 and 8002")
	}
}

func TestCompile_vLLMRecipe(t *testing.T) {
	recipePath := "../../provision/k8s/apps/inference/recipes/north-mini-code-nvfp4.yaml"
	recipe := loadRecipeFile(t, recipePath)

	out, err := Compile(recipe, CompilerOptions{Namespace: "nim-system"})
	if err != nil {
		t.Fatalf("unexpected error compiling vLLM recipe: %v", err)
	}

	// 1. Verify Deployment & Service structure
	if !strings.Contains(out, "kind: Deployment") {
		t.Errorf("expected output to contain kind: Deployment")
	}
	if !strings.Contains(out, "kind: Service") {
		t.Errorf("expected output to contain kind: Service")
	}

	// 2. Verify 3-phase initContainer pattern
	if !strings.Contains(out, "name: depot-hydration-preflight") {
		t.Errorf("missing Phase 1A depot-hydration-preflight container")
	}
	if !strings.Contains(out, "name: model-check") {
		t.Errorf("missing Phase 1B model-check container for vLLM")
	}
	if !strings.Contains(out, "name: cache-flusher") {
		t.Errorf("missing Phase 1C cache-flusher container")
	}

	// 3. Verify vLLM command and passthroughArgs
	if !strings.Contains(out, "python3") || !strings.Contains(out, "vllm.entrypoints.openai.api_server") {
		t.Errorf("missing vLLM entrypoint command")
	}
	if !strings.Contains(out, "--quantization") || !strings.Contains(out, "fp4") {
		t.Errorf("missing passthroughArgs flags in vLLM container args")
	}

	// 4. Verify GB10 nodeSelector and tolerations
	if !strings.Contains(out, "accelerator: gb10") {
		t.Errorf("missing accelerator: gb10 nodeSelector")
	}
	if !strings.Contains(out, "kubernetes.io/arch: arm64") {
		t.Errorf("missing kubernetes.io/arch: arm64 nodeSelector")
	}
}

func TestValidationErrors(t *testing.T) {
	baseRecipe := func() *SparkRecipe {
		return &SparkRecipe{
			APIVersion: "inference.colt.ai/v1alpha1",
			Kind:       "SparkRecipe",
			Metadata: RecipeMetadata{
				Name: "test-model",
			},
			Spec: RecipeSpec{
				Model: ModelSpec{
					ID:        "org/model-test",
					Directory: "models--org--model-test",
					Source:    "huggingface",
				},
				Runtime: RuntimeSpec{
					Engine:               "vllm",
					Image:                "ghcr.io/test/vllm:latest",
					GPUMemoryUtilization: 0.70,
					MaxNumSeqs:           64,
					MaxModelLen:          8192,
				},
				Hardware: HardwareSpec{
					Accelerator: "gb10",
					Arch:        "arm64",
					GPUCount:    1,
				},
				Storage: StorageSpec{
					DepotSource: "/mnt/model-depot/test/models--org--model-test",
					ReadyTarget: "/opt/nim/.cache/huggingface/hub/models--org--model-test",
				},
			},
		}
	}

	t.Run("Valid recipe passes", func(t *testing.T) {
		r := baseRecipe()
		if err := ValidateRecipe(r); err != nil {
			t.Fatalf("expected valid recipe to pass validation, got: %v", err)
		}
	})

	t.Run("Exceeds UMA memory envelope", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Runtime.GPUMemoryUtilization = 0.85
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for gpuMemoryUtilization > 0.75, got nil")
		}
		if !strings.Contains(err.Error(), "exceeds UMA envelope") {
			t.Errorf("unexpected error message: %v", err)
		}
	})

	t.Run("Negative UMA memory envelope", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Runtime.GPUMemoryUtilization = -0.1
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for negative gpuMemoryUtilization, got nil")
		}
	})

	t.Run("Invalid hardware accelerator", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Hardware.Accelerator = "h100"
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for accelerator != gb10, got nil")
		}
		if !strings.Contains(err.Error(), "spec.hardware.accelerator must be 'gb10'") {
			t.Errorf("unexpected error message: %v", err)
		}
	})

	t.Run("Invalid CPU arch", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Hardware.Arch = "x86_64"
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for arch != arm64, got nil")
		}
	})

	t.Run("Invalid depot source path", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Storage.DepotSource = "/var/data/models"
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for depotSource not starting with /mnt/model-depot, got nil")
		}
		if !strings.Contains(err.Error(), "must be rooted in ModelDepot (/mnt/model-depot)") {
			t.Errorf("unexpected error message: %v", err)
		}
	})

	t.Run("Invalid engine", func(t *testing.T) {
		r := baseRecipe()
		r.Spec.Runtime.Engine = "tgi"
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for unsupported engine, got nil")
		}
		if !strings.Contains(err.Error(), "spec.runtime.engine must be 'nim' or 'vllm'") {
			t.Errorf("unexpected error message: %v", err)
		}
	})

	t.Run("Invalid APIVersion", func(t *testing.T) {
		r := baseRecipe()
		r.APIVersion = "v1"
		err := ValidateRecipe(r)
		if err == nil {
			t.Fatal("expected error for invalid apiVersion, got nil")
		}
	})
}
