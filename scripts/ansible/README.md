# Ansible playbooks for opp-policy-chart

- **s3-ssl-certificate-sync.yml** – Wait for ManagedClusters, read CA from vp-manage-proxy-cluster-ca
  (`vp-pattern-proxy-ca-bundle` by default), ensure Proxy.trustedCA on hub/spokes, restart Ramen pods.
  Profile `caCertificates` injection is owned by vp-ramen-s3-ca-injector-chart.
- **s3-ssl-precheck.yml** – Verify hub vp-proxy CA ConfigMap and Proxy.trustedCA.

Shared tasks: `kubeconfig.yml`, `wait-dr-managedclusters-available.yml`, `s3-ssl-read-ca.yml`.
