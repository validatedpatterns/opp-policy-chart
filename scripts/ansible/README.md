# Ansible playbooks (scripts rewrite)

These playbooks replace the bash scripts in `../` and are intended to run inside the **quay.io/validatedpatterns/utility-container:latest** image with the **kubernetes.core** collection available.

- **argocd-health-monitor-job.yml** – One-shot Job: wait for managed clusters, then retry until both primary and secondary Argo CD instances are healthy (force-sync remediation).
- **argocd-health-monitor-cron.yml** – CronJob: check clusters for wedged Argo CD, remediate (force-sync + optional refresh).
- **odf-ssl-certificate-extraction.yml** – Extract CAs from hub and managed clusters, build combined bundle, update hub/managed `cluster-proxy-ca-bundle` / Proxy, restart ramenddr/Velero pods. Ramen hub `caCertificates` are owned by regional DR charts, not this playbook.
- **odf-ssl-precheck.yml** – Wait for clusters, verify certificate distribution on hub; cleanup placeholders; if incomplete, instruct to run/sync the extraction Job.

Kubeconfig retrieval uses the same method as the original scripts: from the hub, list secrets in the managed cluster namespace, use `admin-kubeconfig` or `kubeconfig` secret, then `.data.kubeconfig` or `.data.raw-kubeconfig`; write to `/tmp/<cluster>-kubeconfig.yaml`.

## Install collection

```bash
ansible-galaxy collection install -r requirements.yml
```

## Run locally (against hub)

```bash
export KUBECONFIG=/path/to/hub/kubeconfig
export PRIMARY_CLUSTER=ocp-primary
export SECONDARY_CLUSTER=ocp-secondary

ansible-playbook -i localhost, -c local argocd-health-monitor-job.yml
# or
ansible-playbook -i localhost, -c local odf-ssl-certificate-extraction.yml
```
