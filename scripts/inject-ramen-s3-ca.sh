#!/usr/bin/env bash
# Inject caCertificates into existing Ramen s3StoreProfiles from vp-proxy CA material.
# Prefer CA_FILE (hub-read PEM shared across targets). Else wait for CA ConfigMap in-cluster.
# Never creates profiles. Soft-exit when ALLOW_MISSING_PROFILES=true and profiles are absent.
# Skips ConfigMap apply when every profile already has the desired caCertificates value.
# After a successful patch, restarts Ramen operator pods so they reload process trust
# (Proxy trustedCA). Profile caCertificates alone are not used by Ramen ListKeys.
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

encode_ca_b64() {
	# Never export the CA as an env var — large bundles exceed ARG_MAX and break yq/strenv.
	(base64 -w 0 <"$WORK_DIR/ca-bundle.crt" 2>/dev/null || base64 <"$WORK_DIR/ca-bundle.crt" | tr -d '\n') >"$WORK_DIR/ca-bundle.b64"
	[[ -s "$WORK_DIR/ca-bundle.b64" ]] || die "failed to base64-encode CA bundle"
}

# Return 0 when every s3StoreProfiles entry already has caCertificates equal to desired b64.
profiles_match_desired_ca() {
	local f="$1"
	local desired="$WORK_DIR/ca-bundle.b64"
	local path len i existing

	for path in '.s3StoreProfiles' '.kubeObjectProtection.s3StoreProfiles'; do
		len=$(yq eval "(${path} // []) | length" "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
		[[ "$len" =~ ^[0-9]+$ ]] || len=0
		[[ "$len" -gt 0 ]] || continue
		for ((i = 0; i < len; i++)); do
			existing="$WORK_DIR/existing-ca.${path//./_}.$i"
			# -r + strip newlines so cmp matches base64 -w0 output.
			yq eval -r "${path}[$i].caCertificates // \"\"" "$f" 2>/dev/null | tr -d '\n\r' >"$existing" || true
			if ! cmp -s "$desired" "$existing"; then
				return 1
			fi
		done
	done
	return 0
}

patch_profiles() {
	local f="$WORK_DIR/ramen_manager_config.yaml"
	local out="$WORK_DIR/ramen_manager_config.patched.yaml"
	local ca_b64="$WORK_DIR/ca-bundle.b64"

	encode_ca_b64

	local top_len kop_len
	top_len=$(yq eval '(.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
	kop_len=$(yq eval '(.kubeObjectProtection.s3StoreProfiles // []) | length' "$f" 2>/dev/null | tr -d ' \n\r' || echo 0)
	[[ "$top_len" =~ ^[0-9]+$ ]] || top_len=0
	[[ "$kop_len" =~ ^[0-9]+$ ]] || kop_len=0
	[[ $((top_len + kop_len)) -gt 0 ]] || die "no s3StoreProfiles arrays to patch (top=${top_len} kop=${kop_len})"

	if profiles_match_desired_ca "$f"; then
		log "Unchanged: caCertificates already current on ${RAMEN_NAMESPACE}/${RAMEN_CONFIGMAP} (skip apply)"
		return 0
	fi

	cp "$f" "$out"
	if [[ "$top_len" -gt 0 ]]; then
		yq eval -i ".s3StoreProfiles[] |= . + {\"caCertificates\": load_str(\"${ca_b64}\")}" "$out" \
			|| die "yq failed patching top-level s3StoreProfiles"
	fi
	if [[ "$kop_len" -gt 0 ]]; then
		yq eval -i ".kubeObjectProtection.s3StoreProfiles[] |= . + {\"caCertificates\": load_str(\"${ca_b64}\")}" "$out" \
			|| die "yq failed patching kubeObjectProtection.s3StoreProfiles"
	fi
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
	# Signal verify_patch that an apply happened.
	touch "$WORK_DIR/.ca-patched"
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

# Ramen's S3 ListKeys client uses the process trust store (cluster Proxy trustedCA),
# not s3StoreProfiles.caCertificates. Restart operators after we patch so pods
# remount/reload trust that s3-ssl / vp-proxy just distributed.
restart_ramen_operators() {
	local ns label pods
	local -a labels=("app=ramen-hub-operator" "app=ramen-dr-cluster-operator")

	log "Restarting Ramen operator pods after caCertificates patch..."
	for ns in openshift-operators openshift-dr-system; do
		for label in "${labels[@]}"; do
			pods=$(oc get pods -n "$ns" -l "$label" -o name 2>/dev/null || true)
			if [[ -n "$pods" ]]; then
				log "  Deleting ${label} pods in ${ns}"
				# shellcheck disable=SC2086
				oc delete -n "$ns" $pods --ignore-not-found=true || true
			fi
		done
	done
}

resolve_ca_bundle
wait_for_ramen_profiles
rm -f "$WORK_DIR/.ca-patched"
patch_profiles
if [[ -f "$WORK_DIR/.ca-patched" ]]; then
	verify_patch
	restart_ramen_operators
else
	log "Skip verify and restart (no ConfigMap apply)"
fi
log "Done."
