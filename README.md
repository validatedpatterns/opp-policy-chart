# opp-policy-chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)

ACM/OCM policy chart for Submariner, s3-ssl CA sync, and Ramen s3StoreProfiles CA injection (from vp-manage-proxy-cluster-ca) supporting Regional Disaster Recovery.

Always deployed with **regionaldr-with-virt** (Ramen DR / virt workloads). This chart adds Submariner, s3-ssl CA sync, and Ramen `s3StoreProfiles` CA injection (sourced from **vp-manage-proxy-cluster-ca**) on the hub, with optional distribution to ManagedClusters.
Also pair with **odf-dr-chart** (MirrorPeer / ODF).

**s3-ssl** sync/precheck/policies use the **full** Proxy trustedCA ConfigMap (`vp-pattern-proxy-ca-bundle` / `ca-bundle.crt`) — the same object `Proxy/cluster.spec.trustedCA` must reference.
**s3CaInjector** reads the **differential** Bundle (`vp-pattern-proxy-ca-bundle-differential` / `cabundle` — hub + spoke API/ingress CAs only), patches `ramen-hub-operator-config`, then (when `s3CaInjector.distributeToManagedClusters` is true) uses ACM kubeconfigs to patch `ramen-dr-cluster-operator-config` on spokes. Set `distributeToManagedClusters: false` for hub-only.

## Notable changes

v0.1.0 - Fold s3-ca-injector into this chart (hub + optional spoke inject via ACM kubeconfigs); prefer over standalone vp-ramen-s3-ca-injector; s3-ssl uses the full Proxy trustedCA ConfigMap, s3CaInjector uses the differential Bundle

v0.0.4 - Add Submariner and s3-ssl (from odf-dr); s3-ssl sources CA from vp-proxy ConfigMap

v0.0.3 - Move ObjectBucketClaim and policy-observability-storage to odf-dr chart

v0.0.2 - Remove all ODF templates and scripts and place them separate in odf-dr chart

v0.0.1 - Initial release

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ansible.configMapArgoSyncOptions | string | `"Prune=false,ServerSideApply=true"` | Argo CD resource sync-options applied to the Ansible ConfigMap. |
| ansible.containerImage | string | `"quay.io/validatedpatterns/utility-container:latest"` | Container image used for Ansible post-install jobs. |
| ansible.verbosity | int | `0` | Ansible-playbook verbosity level (0–4). |
| clusterCaMgt.createNamespace | bool | `false` | Create clusterCaMgt.namespace when installing the chart. |
| clusterCaMgt.namespace | string | `"cluster-ca-mgt"` | Namespace for s3-ssl and s3-ca-injector workloads. |
| global.clusterPlatform | string | `"AWS"` | Cloud platform type. AWS enables Submariner gateway/credentials and SG-tag job. |
| regionalDR[0].clusters.primary.name | string | `"ocp-primary"` |  |
| regionalDR[0].clusters.secondary.name | string | `"ocp-secondary"` |  |
| regionalDR[0].globalnetEnabled | bool | `false` | Enable Submariner Globalnet when primary/secondary CIDRs overlap. |
| regionalDR[0].name | string | `"resilient"` | Name of this DR pair set (also Submariner broker ClusterSet name). |
| s3CaInjector.caBundle.key | string | `"cabundle"` | Data key holding PEM (differentialBundle.targetKey; must not contain '.'). |
| s3CaInjector.caBundle.name | string | `"vp-pattern-proxy-ca-bundle-differential"` | Differential Bundle only (API/ingress CAs). Do not use the full Proxy system trust store here. |
| s3CaInjector.caBundle.namespace | string | `"openshift-config"` | Namespace of the differential CA ConfigMap (same targetNamespace as vp-proxy). |
| s3CaInjector.clusterReadinessMaxAttempts | int | `150` | Maximum ManagedCluster readiness poll attempts before injector fails (spoke path). |
| s3CaInjector.clusterReadinessSleepSeconds | int | `30` | Seconds between ManagedCluster readiness polls. |
| s3CaInjector.cronJob.argoCDSyncWave | string | `"10"` | Argo CD sync-wave for the CronJob. |
| s3CaInjector.cronJob.concurrencyPolicy | string | `"Forbid"` | CronJob concurrencyPolicy. |
| s3CaInjector.cronJob.enabled | bool | `true` | Render a CronJob that re-injects after MCO wipes caCertificates. |
| s3CaInjector.cronJob.failedJobsHistoryLimit | int | `3` | failedJobsHistoryLimit. |
| s3CaInjector.cronJob.schedule | string | `"*/15 * * * *"` | Cron schedule (UTC). |
| s3CaInjector.cronJob.successfulJobsHistoryLimit | int | `3` | successfulJobsHistoryLimit. |
| s3CaInjector.cronJob.suspend | bool | `false` | Suspend the CronJob without deleting it. |
| s3CaInjector.distributeToManagedClusters | bool | `true` | When false, patch hub Ramen only (skip ManagedCluster kubeconfigs / spoke inject). |
| s3CaInjector.enabled | bool | `true` | When false, skip the Ramen s3StoreProfiles CA injector Job/CronJob. |
| s3CaInjector.job.activeDeadlineSeconds | int | `14400` | Job activeDeadlineSeconds. |
| s3CaInjector.job.argoCDSyncWave | string | `"10"` | Argo CD sync-wave for the Job. |
| s3CaInjector.job.backoffLimit | int | `5` | Job backoffLimit. |
| s3CaInjector.job.caWaitSeconds | int | `3600` | Seconds to wait for the vp-proxy CA ConfigMap (fallback if CA_FILE unused). |
| s3CaInjector.job.enabled | bool | `true` | Render a one-shot PostSync Job. |
| s3CaInjector.job.pollInterval | int | `15` | Poll interval while waiting. |
| s3CaInjector.job.ramenWaitSeconds | int | `3600` | Seconds to wait for Ramen s3StoreProfiles. |
| s3CaInjector.ramen.configKey | string | `"ramen_manager_config.yaml"` | Key inside the Ramen ConfigMap that holds RamenConfig YAML. |
| s3CaInjector.ramen.failIfNoProfiles | bool | `true` | When true, fail the one-shot Job if profiles never appear. CronJob soft-exits. |
| s3CaInjector.ramen.hubConfigMapName | string | `"ramen-hub-operator-config"` | Hub Ramen ConfigMap name. |
| s3CaInjector.ramen.managedConfigMapName | string | `"ramen-dr-cluster-operator-config"` | Managed-cluster Ramen ConfigMap name. |
| s3CaInjector.ramen.minProfiles | int | `2` | Minimum s3StoreProfiles before patching. |
| s3CaInjector.ramen.namespace | string | `"openshift-operators"` | Namespace of hub and managed Ramen operator ConfigMaps. |
| s3Ssl.caBundle.key | string | `"ca-bundle.crt"` | Data key holding PEM for Proxy trustedCA (usually ca-bundle.crt). |
| s3Ssl.caBundle.name | string | `"vp-pattern-proxy-ca-bundle"` | Full Proxy trustedCA ConfigMap (vp-manage-proxy-cluster-ca configMapName). Not the differential Bundle. |
| s3Ssl.caBundle.namespace | string | `"openshift-config"` | Namespace of the vp-proxy trust ConfigMap (vp-manage-proxy-cluster-ca targetNamespace). |
| s3Ssl.clusterReadinessMaxAttempts | int | `150` | Maximum ManagedCluster readiness poll attempts before sync Job fails. |
| s3Ssl.clusterReadinessSleepSeconds | int | `30` | Seconds between ManagedCluster readiness polls. |
| s3Ssl.enabled | bool | `true` | When false, skip s3-ssl Jobs, playbook ConfigMaps, and ACM CA policies. |
| submariner.NATTEnable | bool | `true` | Enable NAT traversal (NAT-T) for Submariner IPsec tunnels. |
| submariner.cableDriver | string | `"vxlan"` | Submariner cable driver (vxlan or libreswan). |
| submariner.enabled | bool | `true` | When false, skip Submariner Broker, ManagedClusterAddOn, SubmarinerConfig, and related Jobs/RBAC. |
| submariner.instanceType | string | `"m5.xlarge"` | EC2 instance type for Submariner gateway nodes. |
| submariner.ipsecNatPort | int | `4500` | IPsec NAT-T UDP port used by Submariner. |
| submariner.sgTagJobEnabled | bool | `false` | Enable EC2 security group tagging job. AWS only; also requires submariner.enabled. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
