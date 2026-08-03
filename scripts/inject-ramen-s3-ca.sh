#!/usr/bin/env bash
# Inject caCertificates into existing Ramen s3StoreProfiles from vp-proxy CA material.
# Prefer CA_FILE (hub-read PEM shared across targets). Else wait for CA ConfigMap in-cluster.
# Never creates profiles. Soft-exit when ALLOW_MISSING_PROFILES=true and profiles are absent.
# Honors KUBECONFIG for managed-cluster targets (empty/unset = hub in-cluster).
set -euo pipefail

CA_FILE="${CA_FILE:-}"
CA_NAMESPACE="${CA_NAMESPACE:-openshift-config}"
CA_CONFIGMAP="${CA_CONFIGMAP:-vp-pattern-proxy-ca-bundle-differential}"
CA_KEY="${CA_KEY:-cabundle}"
RAMEN_NAMESPACE="${RAMEN_NAMESPACE:?RAMEN_NAMESPACE is required}"
RAMEN_CONFIGMAP="${RAMEN_CONFIGMAP:?RAMEN_CONFIGMAP is required}"
RAMEN_CONFIG_KEY="${RAMEN_CONFIG_KEY:-ramen_manager_config.yaml}"
MIN_PROFILES="${MIN_PROFILES:-1}"
CA_WAIT_SECONDS="${CA_WAIT_SECONDS:-3600}"
RAMEN_WAIT_SECONDS="${RAMEN_WAIT_SECONDS:-3600}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
ALLOW_MISSING_PROFILES="${ALLOW_MISSING_PROFILES:-false}"
WORK_DIR="${WORK_DIR:-/tmp/opp-s3-ca-injector}"

die() {
	echo "ERROR: $*" >&2
	exit 1
}

log() {
	echo "$*"
}

command -v oc >/dev/null 2>&1 || die "oc not found"
command -v yq >/dev/null 2>&1 || die "yq not found (need mikefarah/yq v4)"

mkdir -p "$WORK_DIR"

jsonpath_for_key() {
	local key="$1"
	# jsonpath needs dots escaped in key names
	echo "{.data.$(printf '%s' "$key" | sed 's/\./\\./g')}"
}

resolve_ca_bundle() {
	if [[ -n "$CA_FILE" && -f "$CA_FILE" ]]; then
		local bytes
		bytes=$(wc -c <"$CA_FILE" | tr -d ' ')
		if [[ "${bytes:-0}" -ge 64 ]]; then
			cp "$CA_FILE" "$WORK_DIR/ca-bundle.crt"
			log "Using CA_FILE=${CA_FILE} (${bytes} bytes)"
			return 0
		fi
		die "CA_FILE=${CA_FILE} is too small (${bytes:-0} bytes)"
	fi

	local deadline=$((SECONDS + CA_WAIT_SECONDS))
	local jp
	jp=$(jsonpath_for_key "$CA_KEY")
	log "Waiting for CA ConfigMap ${CA_NAMESPACE}/${CA_CONFIGMAP} key=${CA_KEY} (max ${CA_WAIT_SECONDS}s)..."
	while ((SECONDS < deadline)); do
		local data bytes
		data=$(oc get configmap "$CA_CONFIGMAP" -n "$CA_NAMESPACE" -o "jsonpath=${jp}" 2>/dev/null || true)
		bytes=$(printf '%s' "$data" | wc -c | tr -d ' ')
		if [[ "${bytes:-0}" -ge 64 ]]; then
			printf '%s' "$data" >"$WORK_DIR/ca-bundle.crt"
			log "  CA bundle ready (${bytes} bytes)"
			return 0
		fi
		log "  ... ca bytes=${bytes:-0}, retry in ${POLL_INTERVAL}s"
		sleep "$POLL_INTERVAL"
	done
	die "CA ConfigMap ${CA_NAMESPACE}/${CA_CONFIGMAP} key ${CA_KEY} not ready in time (is vp-manage-proxy-cluster-ca installed?)"
}

count_profiles() {
	local f="$1"
	local k t
	k=$(yq eval '(.kubeObjectProtection.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
	t=$(yq eval '(.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
	[[ "$k" =~ ^[0-9]+$ ]] || k=0
	[[ "$t" =~ ^[0-9]+$ ]] || t=0
	echo $((k > t ? k : t))
}

wait_for_ramen_profiles() {
	local deadline=$((SECONDS + RAMEN_WAIT_SECONDS))
	local f="$WORK_DIR/ramen_manager_config.yaml"
	log "Waiting for ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP} s3StoreProfiles >= ${MIN_PROFILES} (max ${RAMEN_WAIT_SECONDS}s)..."
	while ((SECONDS < deadline)); do
		if ! oc get configmap "$RAMEN_CONFIGMAP" -n "$RAMEN_NAMESPACE" &>/dev/null; then
			log "  ... ConfigMap missing, retry in ${POLL_INTERVAL}s"
			sleep "$POLL_INTERVAL"
			continue
		fi
		oc get configmap "$RAMEN_CONFIGMAP" -n "$RAMEN_NAMESPACE" \
			-o "jsonpath={.data.$(printf '%s' "$RAMEN_CONFIG_KEY" | sed 's/\./\\./g')}" >"$f" 2>/dev/null || true
		if [[ ! -s "$f" ]]; then
			log "  ... empty ${RAMEN_CONFIG_KEY}, retry in ${POLL_INTERVAL}s"
			sleep "$POLL_INTERVAL"
			continue
		fi
		local c
		c=$(count_profiles "$f")
		if [[ "${c:-0}" -ge "$MIN_PROFILES" ]]; then
			log "  s3StoreProfiles ready (count=${c})"
			return 0
		fi
		log "  ... profiles=${c:-0} (need >= ${MIN_PROFILES}), retry in ${POLL_INTERVAL}s"
		sleep "$POLL_INTERVAL"
	done

	if [[ "$ALLOW_MISSING_PROFILES" == "true" ]]; then
		log "WARNING: no s3StoreProfiles yet; soft-exit (ALLOW_MISSING_PROFILES=true)"
		exit 0
	fi
	die "${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP} never gained >= ${MIN_PROFILES} s3StoreProfiles"
}

patch_profiles() {
	local f="$WORK_DIR/ramen_manager_config.yaml"
	local out="$WORK_DIR/ramen_manager_config.patched.yaml"
	local ca_b64="$WORK_DIR/ca-bundle.b64"
	cp "$f" "$out"

	# Never export the CA as an env var — large bundles exceed ARG_MAX and break yq/strenv.
	(base64 -w 0 <"$WORK_DIR/ca-bundle.crt" 2>/dev/null || base64 <"$WORK_DIR/ca-bundle.crt" | tr -d '\n') >"$ca_b64"
	[[ -s "$ca_b64" ]] || die "failed to base64-encode CA bundle"

	local patched=false
	local top_len kop_len
	top_len=$(yq eval '(.s3StoreProfiles // []) | length' "$out" 2>/dev/null | tr -d ' \n\r' || echo 0)
	kop_len=$(yq eval '(.kubeObjectProtection.s3StoreProfiles // []) | length' "$out" 2>/dev/null | tr -d ' \n\r' || echo 0)
	[[ "$top_len" =~ ^[0-9]+$ ]] || top_len=0
	[[ "$kop_len" =~ ^[0-9]+$ ]] || kop_len=0

	if [[ "$top_len" -gt 0 ]]; then
		yq eval -i ".s3StoreProfiles[] |= . + {\"caCertificates\": load_str(\"${ca_b64}\")}" "$out" \
			|| die "yq failed patching top-level s3StoreProfiles"
		patched=true
	fi
	if [[ "$kop_len" -gt 0 ]]; then
		yq eval -i ".kubeObjectProtection.s3StoreProfiles[] |= . + {\"caCertificates\": load_str(\"${ca_b64}\")}" "$out" \
			|| die "yq failed patching kubeObjectProtection.s3StoreProfiles"
		patched=true
	fi
	[[ "$patched" == "true" ]] || die "no s3StoreProfiles arrays to patch (top=${top_len} kop=${kop_len})"
	grep -q 'caCertificates' "$out" || die "patched YAML has no caCertificates"

	# Preserve existing metadata; replace only the RamenConfig data key.
	oc get configmap "$RAMEN_CONFIGMAP" -n "$RAMEN_NAMESPACE" -o yaml >"$WORK_DIR/ramen-cm-live.yaml" \
		|| die "failed to get ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP}"
	# Strip volatile fields that confuse apply.
	yq eval -i 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation, .metadata.managedFields, .status)' \
		"$WORK_DIR/ramen-cm-live.yaml"
	# Prefer quoted key form; avoid strenv for the large YAML payload.
	yq eval -i ".data.\"${RAMEN_CONFIG_KEY}\" = load_str(\"${out}\")" "$WORK_DIR/ramen-cm-live.yaml" \
		|| die "failed to set ${RAMEN_CONFIG_KEY} on ConfigMap manifest"

	oc apply -f "$WORK_DIR/ramen-cm-live.yaml" || die "oc apply failed for ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP}"
	log "Patched caCertificates on s3StoreProfiles in ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP}"
}

verify_patch() {
	local f="$WORK_DIR/ramen-post-apply.yaml"
	local attempt pk pt ck ct
	for attempt in $(seq 1 8); do
		[[ "$attempt" -gt 1 ]] && sleep 3
		oc get configmap "$RAMEN_CONFIGMAP" -n "$RAMEN_NAMESPACE" \
			-o "jsonpath={.data.$(printf '%s' "$RAMEN_CONFIG_KEY" | sed 's/\./\\./g')}" >"$f" 2>/dev/null || continue
		[[ -s "$f" ]] || continue
		pk=$(yq eval '(.kubeObjectProtection.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
		pt=$(yq eval '(.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
		ck=$(yq eval '[(.kubeObjectProtection.s3StoreProfiles // [])[]? | select(has("caCertificates"))] | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
		ct=$(yq eval '[(.s3StoreProfiles // [])[]? | select(has("caCertificates"))] | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
		[[ "$pk" =~ ^[0-9]+$ ]] || pk=0
		[[ "$pt" =~ ^[0-9]+$ ]] || pt=0
		[[ "$ck" =~ ^[0-9]+$ ]] || ck=0
		[[ "$ct" =~ ^[0-9]+$ ]] || ct=0
		if [[ "$pk" -gt 0 && "$ck" -lt "$pk" ]]; then
			continue
		fi
		if [[ "$pt" -gt 0 && "$ct" -lt "$pt" ]]; then
			continue
		fi
		if [[ $((pk > pt ? pk : pt)) -ge "$MIN_PROFILES" ]]; then
			log "Verified: kubeObjectProtection ${ck}/${pk}, top-level ${ct}/${pt}"
			return 0
		fi
	done
	die "post-apply verification failed for ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP}"
}

resolve_ca_bundle
wait_for_ramen_profiles
patch_profiles
verify_patch
log "Done."
