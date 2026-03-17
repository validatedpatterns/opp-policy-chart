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

{{/* Managed clustergroup namespace: "<pattern>-<clustergroup>" (e.g. ramendr-techdemo-resilient), same convention as Application name.
     Precedence: 1) argocdHealthMonitor.managedClusterGroupNamespace (explicit)
     2) pattern name (global.pattern / patternName) + "-" + clustergroup name from clusterGroup.managedClusterGroups / regionalDR. */}}
{{- define "opp.managedClusterGroupNamespace" -}}
{{- $explicit := .Values.argocdHealthMonitor.managedClusterGroupNamespace | default "" -}}
{{- if $explicit }}{{ $explicit }}{{- else -}}
  {{- $patternName := .Values.argocdHealthMonitor.patternName | default (index (.Values.global | default dict) "pattern") | default "ramendr-starter-kit" -}}
  {{- $cgName := include "opp.managedClusterGroupName" . -}}
  {{- if $cgName }}{{ printf "%s-%s" $patternName $cgName }}{{- else -}}{{ fail "managed clustergroup name required: set clusterGroup.managedClusterGroups[0].name (from values-hub), managedClusterGroups[0].name, managedClusterGroupName, regionalDR[0].name, or argocdHealthMonitor.managedClusterGroupNamespace" }}{{- end -}}
{{- end -}}
{{- end -}}

{{/* Short managed clustergroup name. Same precedence as namespace; when namespace is explicit, derived as last segment after "-". */}}
{{- define "opp.managedClusterGroupName" -}}
{{- $explicitNs := .Values.argocdHealthMonitor.managedClusterGroupNamespace | default "" -}}
{{- if $explicitNs }}{{ .Values.managedClusterGroupName | default (index (splitList "-" $explicitNs) (sub (len (splitList "-" $explicitNs)) 1)) }}{{- else -}}
  {{- $cg := .Values.clusterGroup | default dict -}}
  {{- $mcgRawChart := $cg.managedClusterGroups | default list -}}
  {{- $mcgRawTop := .Values.managedClusterGroups | default list -}}
  {{- $mcgFromChart := dict -}}
  {{- if gt (len $mcgRawChart) 0 }}{{ if eq (kindOf $mcgRawChart) "slice" }}{{ $mcgFromChart = first $mcgRawChart }}{{ else }}{{ $mcgFromChart = first (values $mcgRawChart) }}{{ end }}{{ end -}}
  {{- $mcgTop := dict -}}
  {{- if gt (len $mcgRawTop) 0 }}{{ if eq (kindOf $mcgRawTop) "slice" }}{{ $mcgTop = first $mcgRawTop }}{{ else }}{{ $mcgTop = first (values $mcgRawTop) }}{{ end }}{{ end -}}
  {{- $firstDR := index (.Values.regionalDR | default list) 0 | default dict -}}
  {{- .Values.managedClusterGroupName | default $mcgFromChart.name | default $mcgTop.name | default $firstDR.name -}}
{{- end -}}
{{- end -}}

{{/* Force-sync Application name: "<pattern name>-<clustergroup name>" (e.g. ramendr-techdemo-resilient). */}}
{{- define "opp.forceSyncAppName" -}}
{{- $explicit := .Values.argocdHealthMonitor.forceSyncAppName | default "" -}}
{{- if $explicit }}{{ $explicit }}{{- else -}}
  {{- $patternName := .Values.argocdHealthMonitor.patternName | default (index (.Values.global | default dict) "pattern") | default "ramendr-starter-kit" -}}
  {{- $cgName := include "opp.managedClusterGroupName" . -}}
  {{- printf "%s-%s" $patternName $cgName -}}
{{- end -}}
{{- end -}}

{{/* JSON array of force-sync resources: only the managed clustergroup namespace (single Namespace). */}}
{{- define "opp.forceSyncResourcesJson" -}}
{{- $ns := include "opp.managedClusterGroupNamespace" . -}}
{{- $list := list (dict "kind" "Namespace" "name" $ns) -}}
{{- $list | toJson -}}
{{- end -}}
