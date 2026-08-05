{{- define "opp.s3CaInjector.commonEnv" -}}
- name: PRIMARY_CLUSTER
  value: {{ include "opp.primaryClusterName" . | quote }}
- name: SECONDARY_CLUSTER
  value: {{ include "opp.secondaryClusterName" . | quote }}
- name: ANSIBLE_NOCOLOR
  value: "true"
- name: CA_BUNDLE_NAME
  value: {{ include "opp.s3CaInjectorCaBundleName" . | quote }}
- name: CA_BUNDLE_NAMESPACE
  value: {{ include "opp.s3CaInjectorCaBundleNamespace" . | quote }}
- name: CA_BUNDLE_KEY
  value: {{ include "opp.s3CaInjectorCaBundleKey" . | quote }}
- name: RAMEN_NAMESPACE
  value: {{ include "opp.ramenNamespace" . | quote }}
- name: RAMEN_HUB_CONFIGMAP
  value: {{ include "opp.ramenHubConfigMapName" . | quote }}
- name: RAMEN_MANAGED_CONFIGMAP
  value: {{ include "opp.ramenManagedConfigMapName" . | quote }}
- name: RAMEN_CONFIG_KEY
  value: {{ (((.Values.s3CaInjector | default dict).ramen | default dict).configKey | default "ramen_manager_config.yaml") | quote }}
- name: MIN_PROFILES
  value: {{ (((.Values.s3CaInjector | default dict).ramen | default dict).minProfiles | default 1) | quote }}
- name: DISTRIBUTE_TO_MANAGED_CLUSTERS
  value: {{ include "opp.s3CaInjectorDistributeToManaged" . | quote }}
- name: CLUSTER_READINESS_MAX_ATTEMPTS
  value: {{ (((.Values.s3CaInjector | default dict).clusterReadinessMaxAttempts | default ((.Values.s3Ssl | default dict).clusterReadinessMaxAttempts | default 150))) | quote }}
- name: CLUSTER_READINESS_SLEEP_SECONDS
  value: {{ (((.Values.s3CaInjector | default dict).clusterReadinessSleepSeconds | default ((.Values.s3Ssl | default dict).clusterReadinessSleepSeconds | default 30))) | quote }}
- name: INJECT_SCRIPT
  value: "/scripts/inject-ramen-s3-ca.sh"
{{- end }}

{{- define "opp.s3CaInjector.volumeMounts" -}}
- name: playbooks
  mountPath: /playbooks
  readOnly: true
- name: script
  mountPath: /scripts
  readOnly: true
{{- end }}

{{- define "opp.s3CaInjector.volumes" -}}
- name: playbooks
  configMap:
    name: s3-ca-injector-playbooks
    items:
    - key: s3-ca-injector.yml # gitleaks:allow ConfigMap key name, not a credential
      path: s3-ca-injector.yml
    - key: tasks_kubeconfig.yml
      path: tasks/kubeconfig.yml
    - key: tasks_kubeconfig_attempt.yml
      path: tasks/kubeconfig-attempt.yml
    - key: tasks_s3_ssl_read_ca.yml
      path: tasks/s3-ssl-read-ca.yml
    - key: tasks_wait_dr_managedclusters_available.yml
      path: tasks/wait-dr-managedclusters-available.yml
- name: script
  configMap:
    name: s3-ca-injector-script
    defaultMode: 0555
{{- end }}
