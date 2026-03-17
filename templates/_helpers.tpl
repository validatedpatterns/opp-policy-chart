{{/* Primary cluster name: clusterOverrides.primary.name else regionalDR[0].clusters.primary.name else ocp-primary */}}
{{- define "opp.primaryClusterName" -}}
{{- $over := index (.Values.clusterOverrides | default dict) "primary" | default dict -}}
{{- $fromOver := index $over "name" -}}
{{- if $fromOver }}{{ $fromOver }}{{- else if and .Values.regionalDR (index .Values.regionalDR 0) }}{{ (index .Values.regionalDR 0).clusters.primary.name | default "ocp-primary" }}{{- else }}ocp-primary{{ end -}}
{{- end -}}

{{/* Secondary cluster name */}}
{{- define "opp.secondaryClusterName" -}}
{{- $over := index (.Values.clusterOverrides | default dict) "secondary" | default dict -}}
{{- $fromOver := index $over "name" -}}
{{- if $fromOver }}{{ $fromOver }}{{- else if and .Values.regionalDR (index .Values.regionalDR 0) }}{{ (index .Values.regionalDR 0).clusters.secondary.name | default "ocp-secondary" }}{{- else }}ocp-secondary{{ end -}}
{{- end -}}

{{/* Managed clustergroup namespace: from Validated Patterns managedClusterGroups (clusterGroup chart) or overrides.
     Precedence: 1) argocdHealthMonitor.managedClusterGroupNamespace (explicit)
     2) clusterGroup.managedClusterGroups[0].name (framework block) → ramendr-starter-kit-<name>
     3) managedClusterGroups[0].name (values-hub top-level) → ramendr-starter-kit-<name>
     4) managedClusterGroupName (override) → ramendr-starter-kit-<name>
     5) regionalDR[0].name (this chart) → ramendr-starter-kit-<name>
     No hard-coded default; one of the above must be set. */}}
{{- define "opp.managedClusterGroupNamespace" -}}
{{- $explicit := .Values.argocdHealthMonitor.managedClusterGroupNamespace | default "" -}}
{{- if $explicit }}{{ $explicit }}{{- else -}}
  {{- $cg := .Values.clusterGroup | default dict -}}
  {{- $mcgListChart := $cg.managedClusterGroups | default list -}}
  {{- $mcgListTop := .Values.managedClusterGroups | default list -}}
  {{- $mcgFromChart := dict -}}
  {{- if gt (len $mcgListChart) 0 }}{{ $mcgFromChart = index $mcgListChart 0 }}{{ end -}}
  {{- $mcgTop := dict -}}
  {{- if gt (len $mcgListTop) 0 }}{{ $mcgTop = index $mcgListTop 0 }}{{ end -}}
  {{- $firstDR := index (.Values.regionalDR | default list) 0 | default dict -}}
  {{- $cgName := .Values.managedClusterGroupName | default $mcgFromChart.name | default $mcgTop.name | default $firstDR.name -}}
  {{- if $cgName }}{{ printf "ramendr-starter-kit-%s" $cgName }}{{- else -}}{{ fail "managed clustergroup name required: set clusterGroup.managedClusterGroups[0].name (from values-hub), managedClusterGroups[0].name, managedClusterGroupName, regionalDR[0].name, or argocdHealthMonitor.managedClusterGroupNamespace" }}{{- end -}}
{{- end -}}
{{- end -}}

{{/* Force-sync Application name: same derivation as managed clustergroup namespace (clusterGroup.managedClusterGroups, etc.). */}}
{{- define "opp.forceSyncAppName" -}}
{{- include "opp.managedClusterGroupNamespace" . -}}
{{- end -}}

{{/* JSON array of force-sync resources: only the managed clustergroup namespace (single Namespace). */}}
{{- define "opp.forceSyncResourcesJson" -}}
{{- $ns := include "opp.managedClusterGroupNamespace" . -}}
{{- $list := list (dict "kind" "Namespace" "name" $ns) -}}
{{- $list | toJson -}}
{{- end -}}
