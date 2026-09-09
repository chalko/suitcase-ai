package main

// SparkRecipe represents an inference workload specification for the GB10 appliance.
type SparkRecipe struct {
	APIVersion string         `yaml:"apiVersion"`
	Kind       string         `yaml:"kind"`
	Metadata   RecipeMetadata `yaml:"metadata"`
	Spec       RecipeSpec     `yaml:"spec"`
}

// RecipeMetadata contains metadata annotations and names for the recipe.
type RecipeMetadata struct {
	Name   string            `yaml:"name"`
	Labels map[string]string `yaml:"labels,omitempty"`
}

// RecipeSpec defines the full model, runtime, hardware, and storage parameters.
type RecipeSpec struct {
	Model    ModelSpec    `yaml:"model"`
	Runtime  RuntimeSpec  `yaml:"runtime"`
	Hardware HardwareSpec `yaml:"hardware"`
	Storage  StorageSpec  `yaml:"storage"`
}

// ModelSpec defines upstream model IDs, directory naming, and provenance source.
type ModelSpec struct {
	ID        string `yaml:"id"`
	Directory string `yaml:"directory"`
	Source    string `yaml:"source"`
}

// RuntimeSpec specifies the inference engine, container image, profile, and tuning limits.
type RuntimeSpec struct {
	Engine               string  `yaml:"engine"`
	Image                string  `yaml:"image"`
	Profile              string  `yaml:"profile,omitempty"`
	GPUMemoryUtilization float64 `yaml:"gpuMemoryUtilization"`
	MaxNumSeqs           int     `yaml:"maxNumSeqs,omitempty"`
	MaxModelLen          int     `yaml:"maxModelLen,omitempty"`
	PassthroughArgs      string  `yaml:"passthroughArgs,omitempty"`
}

// HardwareSpec defines target accelerator and CPU architecture.
type HardwareSpec struct {
	Accelerator string `yaml:"accelerator"`
	Arch        string `yaml:"arch"`
	GPUCount    int    `yaml:"gpuCount"`
}

// StorageSpec defines ModelDepot source and ReadyLocker target cache paths.
type StorageSpec struct {
	DepotSource string `yaml:"depotSource"`
	ReadyTarget string `yaml:"readyTarget"`
}

// Kubernetes Data Models

// K8sObjectMeta defines common Kubernetes metadata.
type K8sObjectMeta struct {
	Name      string            `yaml:"name,omitempty"`
	Namespace string            `yaml:"namespace,omitempty"`
	Labels    map[string]string `yaml:"labels,omitempty"`
}

// Deployment defines a Kubernetes apps/v1 Deployment.
type Deployment struct {
	APIVersion string         `yaml:"apiVersion"`
	Kind       string         `yaml:"kind"`
	Metadata   K8sObjectMeta  `yaml:"metadata"`
	Spec       DeploymentSpec `yaml:"spec"`
}

// DeploymentSpec defines deployment execution details.
type DeploymentSpec struct {
	Replicas int                `yaml:"replicas"`
	Strategy DeploymentStrategy `yaml:"strategy"`
	Selector LabelSelector      `yaml:"selector"`
	Template PodTemplateSpec    `yaml:"template"`
}

// DeploymentStrategy defines deployment update strategies.
type DeploymentStrategy struct {
	Type string `yaml:"type"`
}

// LabelSelector defines label matching for selectors.
type LabelSelector struct {
	MatchLabels map[string]string `yaml:"matchLabels"`
}

// PodTemplateSpec defines pod metadata and spec in deployments.
type PodTemplateSpec struct {
	Metadata K8sObjectMeta `yaml:"metadata"`
	Spec     PodSpec       `yaml:"spec"`
}

// PodSpec defines pod runtime configurations.
type PodSpec struct {
	NodeSelector     map[string]string      `yaml:"nodeSelector"`
	RuntimeClassName string                 `yaml:"runtimeClassName"`
	HostNetwork      bool                   `yaml:"hostNetwork"`
	DNSPolicy        string                 `yaml:"dnsPolicy"`
	ImagePullSecrets []LocalObjectReference `yaml:"imagePullSecrets,omitempty"`
	Tolerations      []Toleration           `yaml:"tolerations"`
	InitContainers   []Container            `yaml:"initContainers"`
	Containers       []Container            `yaml:"containers"`
	Volumes          []Volume               `yaml:"volumes"`
}

// LocalObjectReference references a secret or other local object.
type LocalObjectReference struct {
	Name string `yaml:"name"`
}

// Toleration defines pod toleration rules.
type Toleration struct {
	Key      string `yaml:"key"`
	Operator string `yaml:"operator"`
	Value    string `yaml:"value,omitempty"`
	Effect   string `yaml:"effect"`
}

// Container defines a container within a pod.
type Container struct {
	Name            string               `yaml:"name"`
	Image           string               `yaml:"image"`
	ImagePullPolicy string               `yaml:"imagePullPolicy"`
	SecurityContext *SecurityContext     `yaml:"securityContext,omitempty"`
	Command         []string             `yaml:"command,omitempty"`
	Args            []string             `yaml:"args,omitempty"`
	Env             []EnvVar             `yaml:"env,omitempty"`
	Ports           []ContainerPort      `yaml:"ports,omitempty"`
	Resources       ResourceRequirements `yaml:"resources"`
	VolumeMounts    []VolumeMount        `yaml:"volumeMounts"`
	StartupProbe    *Probe               `yaml:"startupProbe,omitempty"`
	LivenessProbe   *Probe               `yaml:"livenessProbe,omitempty"`
	ReadinessProbe  *Probe               `yaml:"readinessProbe,omitempty"`
}

// SecurityContext defines container security settings.
type SecurityContext struct {
	Privileged bool `yaml:"privileged,omitempty"`
}

// EnvVar defines environment variables.
type EnvVar struct {
	Name      string        `yaml:"name"`
	Value     string        `yaml:"value,omitempty"`
	ValueFrom *EnvVarSource `yaml:"valueFrom,omitempty"`
}

// EnvVarSource references external sources like secrets.
type EnvVarSource struct {
	SecretKeyRef *SecretKeySelector `yaml:"secretKeyRef,omitempty"`
}

// SecretKeySelector selects a key of a Secret.
type SecretKeySelector struct {
	Name string `yaml:"name"`
	Key  string `yaml:"key"`
}

// ContainerPort defines network ports exposed by a container.
type ContainerPort struct {
	Name          string `yaml:"name"`
	ContainerPort int    `yaml:"containerPort"`
	Protocol      string `yaml:"protocol"`
}

// ResourceRequirements defines compute resource requests and limits.
type ResourceRequirements struct {
	Requests map[string]string `yaml:"requests"`
	Limits   map[string]string `yaml:"limits"`
}

// VolumeMount defines a mount inside a container.
type VolumeMount struct {
	Name      string `yaml:"name"`
	MountPath string `yaml:"mountPath"`
	ReadOnly  bool   `yaml:"readOnly,omitempty"`
}

// Probe defines container liveness/readiness/startup probes.
type Probe struct {
	HTTPGet             *HTTPGetAction `yaml:"httpGet,omitempty"`
	InitialDelaySeconds int            `yaml:"initialDelaySeconds"`
	PeriodSeconds       int            `yaml:"periodSeconds"`
	TimeoutSeconds      int            `yaml:"timeoutSeconds"`
	FailureThreshold    int            `yaml:"failureThreshold"`
}

// HTTPGetAction defines HTTP probe settings.
type HTTPGetAction struct {
	Path string `yaml:"path"`
	Port int    `yaml:"port"`
}

// Volume defines storage volume attached to a pod.
type Volume struct {
	Name     string        `yaml:"name"`
	HostPath *HostPathSpec `yaml:"hostPath,omitempty"`
	EmptyDir *EmptyDirSpec `yaml:"emptyDir,omitempty"`
}

// HostPathSpec defines host filesystem volume properties.
type HostPathSpec struct {
	Path string `yaml:"path"`
	Type string `yaml:"type,omitempty"`
}

// EmptyDirSpec defines emptyDir volume properties.
type EmptyDirSpec struct {
	Medium    string `yaml:"medium,omitempty"`
	SizeLimit string `yaml:"sizeLimit,omitempty"`
}

// Service defines a Kubernetes v1 Service.
type Service struct {
	APIVersion string        `yaml:"apiVersion"`
	Kind       string        `yaml:"kind"`
	Metadata   K8sObjectMeta `yaml:"metadata"`
	Spec       ServiceSpec   `yaml:"spec"`
}

// ServiceSpec defines service port mapping and routing.
type ServiceSpec struct {
	Type     string            `yaml:"type"`
	Selector map[string]string `yaml:"selector"`
	Ports    []ServicePort     `yaml:"ports"`
}

// ServicePort defines port bindings on a Service.
type ServicePort struct {
	Name       string `yaml:"name"`
	Port       int    `yaml:"port"`
	TargetPort int    `yaml:"targetPort"`
	Protocol   string `yaml:"protocol"`
}
