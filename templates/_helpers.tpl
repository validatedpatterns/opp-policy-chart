{{/* Primary cluster name: clusterOverrides.primary.name else regionalDR[0].clusters.primary.name */}}
{{- define "opp.primaryClusterName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $override := index (index (.Values.clusterOverrides | default dict) "primary" | default dict) "name" -}}
{{- $fallback := index (index ($dr.clusters | default dict) "primary" | default dict) "name" -}}
{{- $override | default $fallback | default "ocp-primary" -}}
{{- end -}}

{{/* Secondary cluster name */}}
{{- define "opp.secondaryClusterName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $override := index (index (.Values.clusterOverrides | default dict) "secondary" | default dict) "name" -}}
{{- $fallback := index (index ($dr.clusters | default dict) "secondary" | default dict) "name" -}}
{{- $override | default $fallback | default "ocp-secondary" -}}
{{- end -}}

{{/* Namespace for s3-ssl / CA post-install Jobs */}}
{{- define "opp.clusterCaMgtNamespace" -}}
{{- .Values.clusterCaMgt.namespace | default "cluster-ca-mgt" -}}
{{- end -}}

{{/* regionalDR[0].name (ClusterSet); Submariner broker namespace = name + "-broker" */}}
{{- define "opp.regionalDRClusterSetName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $dr.name -}}
{{- end -}}

{{- define "opp.submarinerBrokerNamespace" -}}
{{ include "opp.regionalDRClusterSetName" . }}-broker
{{- end -}}

{{/* global.clusterPlatform: AWS gates Submariner SG-tag job. Case-insensitive; default AWS. */}}
{{- define "opp.clusterPlatformAws" -}}
{{- $g := .Values.global | default dict -}}
{{- if eq "aws" (lower ($g.clusterPlatform | default "AWS" | toString)) -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* Submariner EC2 SG tagger: AWS platform and submariner.sgTagJobEnabled true. */}}
{{- define "opp.submarinerSgTagJobEnabled" -}}
{{- $sm := .Values.submariner | default dict -}}
{{- $aws := eq "1" (include "opp.clusterPlatformAws" . | trim) -}}
{{- $want := and (hasKey $sm "sgTagJobEnabled") (index $sm "sgTagJobEnabled") -}}
{{- if and $aws $want -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* s3-ssl jobs/policies: sync/verify CA from vp-manage-proxy-cluster-ca. Default on. */}}
{{- define "opp.s3SslEnabled" -}}
{{- $cfg := .Values.s3Ssl | default dict -}}
{{- if not (hasKey $cfg "enabled") -}}1{{- else if index $cfg "enabled" -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* CA ConfigMap produced by vp-manage-proxy-cluster-ca (source for s3-ssl). */}}
{{- define "opp.s3SslCaBundleName" -}}
{{- $cfg := .Values.s3Ssl | default dict -}}
{{- $ca := $cfg.caBundle | default dict -}}
{{- $ca.name | default "vp-pattern-proxy-ca-bundle-differential" -}}
{{- end -}}

{{- define "opp.s3SslCaBundleNamespace" -}}
{{- $cfg := .Values.s3Ssl | default dict -}}
{{- $ca := $cfg.caBundle | default dict -}}
{{- $ca.namespace | default "openshift-config" -}}
{{- end -}}

{{- define "opp.s3SslCaBundleKey" -}}
{{- $cfg := .Values.s3Ssl | default dict -}}
{{- $ca := $cfg.caBundle | default dict -}}
{{- $ca.key | default "cabundle" -}}
{{- end -}}

{{/* Stable checksum of packaged ansible/ (excludes dotfiles). */}}
{{- define "opp.ansibleConfigChecksum" -}}
{{- $paths := list -}}
{{- range $path, $_ := .Files.Glob "ansible/**" -}}
{{- if not (hasPrefix "ansible/." $path) -}}
{{- $paths = append $paths $path -}}
{{- end -}}
{{- end -}}
{{- $buf := "" -}}
{{- range $path := $paths | sortAlpha -}}
{{- $buf = printf "%s\n%s\n%s" $buf $path ($.Files.Get $path) -}}
{{- end -}}
{{- $buf | sha256sum -}}
{{- end -}}

{{- define "opp.ansibleConfigMapArgoSyncOptions" -}}
{{- .Values.ansible.configMapArgoSyncOptions | default "Prune=false,ServerSideApply=true" -}}
{{- end -}}

{{- define "opp.ansibleJobPodAnnotations" -}}
checksum/opp-policy-ansible: {{ include "opp.ansibleConfigChecksum" . | quote }}
{{- end -}}

{{/* Inject caCertificates into Ramen s3StoreProfiles. Default on. */}}
{{- define "opp.s3CaInjectorEnabled" -}}
{{- $cfg := .Values.s3CaInjector | default dict -}}
{{- if not (hasKey $cfg "enabled") -}}1{{- else if index $cfg "enabled" -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* Also patch managed-cluster Ramen ConfigMaps via ACM kubeconfigs. Default on. */}}
{{- define "opp.s3CaInjectorDistributeToManaged" -}}
{{- $cfg := .Values.s3CaInjector | default dict -}}
{{- if not (hasKey $cfg "distributeToManagedClusters") -}}true{{- else if index $cfg "distributeToManagedClusters" -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "opp.ramenNamespace" -}}
{{- $inj := .Values.s3CaInjector | default dict -}}
{{- $r := $inj.ramen | default dict -}}
{{- $r.namespace | default "openshift-operators" -}}
{{- end -}}

{{- define "opp.ramenHubConfigMapName" -}}
{{- $inj := .Values.s3CaInjector | default dict -}}
{{- $r := $inj.ramen | default dict -}}
{{- $r.hubConfigMapName | default "ramen-hub-operator-config" -}}
{{- end -}}

{{- define "opp.ramenManagedConfigMapName" -}}
{{- $inj := .Values.s3CaInjector | default dict -}}
{{- $r := $inj.ramen | default dict -}}
{{- $r.managedConfigMapName | default "ramen-dr-cluster-operator-config" -}}
{{- end -}}
