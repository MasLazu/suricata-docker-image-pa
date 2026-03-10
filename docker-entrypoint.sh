#! /bin/bash

set -e

fix_perms() {
    if [[ "${PGID}" ]]; then
        groupmod -o -g "${PGID}" suricata
    fi

    if [[ "${PUID}" ]]; then
        usermod -o -u "${PUID}" suricata
    fi

    chown -R suricata:suricata /etc/suricata
    chown -R suricata:suricata /var/lib/suricata
    chown -R suricata:suricata /var/log/suricata
    chown -R suricata:suricata /var/run/suricata
}

for src in /etc/suricata.dist/*; do
    filename=$(basename ${src})
    dst="/etc/suricata/${filename}"
    if ! test -e "${dst}"; then
        echo "Creating ${dst}."
        cp -a "${src}" "${dst}"
    fi
done

# Render suricata.yaml from template using sed
MODE=${SURICATA_MODE:-ids}
TEMPLATE=/templates/${MODE}.suricata.yaml.tmpl
if [ -f "$TEMPLATE" ]; then
    # Check required environment variables
    if [ -z "$HOME_NET" ]; then
        echo "Error: HOME_NET environment variable is required"
        exit 1
    fi
    if [ -z "$INTERFACE1" ]; then
        echo "Error: INTERFACE1 environment variable is required"
        exit 1
    fi
    if [ -z "$INTERFACE2" ]; then
        echo "Error: INTERFACE2 environment variable is required"
        exit 1
    fi
    # Check if interfaces exist
    if ! ip link show "$INTERFACE1" > /dev/null 2>&1; then
        echo "Error: Interface $INTERFACE1 not found on the host"
        exit 1
    fi
    if ! ip link show "$INTERFACE2" > /dev/null 2>&1; then
        echo "Error: Interface $INTERFACE2 not found on the host"
        exit 1
    fi
    echo "Rendering ${TEMPLATE} to /etc/suricata/suricata.yaml"

    pcap_mode="${PCAP_MODE:-off}"
    pcap_dir="${PCAP_DIR:-pcap}"
    pcap_limit="${PCAP_LIMIT:-100mb}"
    pcap_max_files="${PCAP_MAX_FILES:-1000}"

    # Suricata pcap-log filename is treated under the Suricata log dir, so prefer a relative path.
    pcap_dir_rel="${pcap_dir#/var/log/suricata/}"
    pcap_dir_rel="${pcap_dir_rel#/}"
    pcap_dir_host="/var/log/suricata/${pcap_dir_rel}"

    pcap_block=""
    case "${pcap_mode}" in
        off|none|"")
            ;;
        all)
            mkdir -p "${pcap_dir_host}/all"
            pcap_block=$(cat <<EOF
  - pcap-log:
      enabled: yes
      filename: ${pcap_dir_rel}/all/all.pcap
      limit: ${pcap_limit}
      max-files: ${pcap_max_files}
      compression: none
      mode: normal
      use-stream-depth: no
      honor-pass-rules: no
EOF
)
            ;;
        alerts)
            mkdir -p "${pcap_dir_host}/alerts"
            pcap_block=$(cat <<EOF
  - pcap-log:
      enabled: yes
      filename: ${pcap_dir_rel}/alerts/alerts.pcap
      limit: ${pcap_limit}
      max-files: ${pcap_max_files}
      compression: none
      mode: normal
      conditional: alerts
      use-stream-depth: no
      honor-pass-rules: no
EOF
)
            ;;
        tag)
            mkdir -p "${pcap_dir_host}/tag"
            pcap_block=$(cat <<EOF
  - pcap-log:
      enabled: yes
      filename: ${pcap_dir_rel}/tag/tag.pcap
      limit: ${pcap_limit}
      max-files: ${pcap_max_files}
      compression: none
      mode: normal
      conditional: tag
      use-stream-depth: no
      honor-pass-rules: no
EOF
)
            ;;
        *)
            echo "Error: unsupported PCAP_MODE '${pcap_mode}'. Use one of: off, all, alerts, tag"
            exit 1
            ;;
    esac

    tmp_render=$(mktemp)
    sed \
        -e "s|{{ home_net }}|${HOME_NET}|g" \
        -e "s|{{ http_ports }}|${HTTP_PORTS:-80}|g" \
        -e "s|{{ ssh_ports }}|${SSH_PORTS:-22}|g" \
        -e "s|{{ interface1 }}|${INTERFACE1}|g" \
        -e "s|{{ interface2 }}|${INTERFACE2}|g" \
        "$TEMPLATE" > "${tmp_render}"

    python3 - <<'PY' "${tmp_render}" "${pcap_block}"
from pathlib import Path
import sys
path = Path(sys.argv[1])
pcap_block = sys.argv[2]
text = path.read_text()
text = text.replace("{{ pcap_output }}", pcap_block.rstrip())
path.write_text(text)
PY

    mv "${tmp_render}" /etc/suricata/suricata.yaml
fi

# If the first command does not look like argument, assume its a
# command the user wants to run. Normally I wouldn't do this.
if [ $# -gt 0 -a "${1:0:1}" != "-" ]; then
    exec $@
fi

run_as_user="yes"

check_for_cap() {
    echo -n "Checking for capability $1: "
    if getpcaps 0 2>&1 | grep -q "$1"; then
        echo "yes"
        return 0
    else
        echo "no"
        return 1
    fi
}

if ! check_for_cap sys_nice; then
    echo "Warning: no sys_nice capability, use --cap-add sys_nice"
    run_as_user="no"
fi
if ! check_for_cap net_admin; then
    echo "Warning: no net_admin capability, use --cap-add net_admin"
    run_as_user="no"
fi

ARGS=""

if [[ "${run_as_user}" != "yes" ]]; then
    echo "Warning: running as root due to missing capabilities" > /dev/stderr
else
    fix_perms
    ARGS="${ARGS} --user suricata --group suricata"
fi

# run helper processes
if [[ "$ENABLE_CRON" == "yes" ]]; then
    crond
fi

# Start IP reputation polling in background if configured
if [[ -n "${IPREP_BASE_URL}" ]]; then
    echo "Starting IP reputation polling from ${IPREP_BASE_URL} every ${IPREP_POLL_INTERVAL_SECONDS:-300}s"
    /usr/local/bin/fetch-ipreputation.sh run &
fi

# Check and update rules if suricata.rules does not exist
if [ ! -f /var/lib/suricata/rules/suricata.rules ]; then
    echo "Suricata rules not found, running suricata-update..."
    suricata-update --no-test --no-reload
fi

# run primary process
exec /usr/bin/suricata ${ARGS} ${SURICATA_OPTIONS} -c /etc/suricata/suricata.yaml -i ${INTERFACE1} -i ${INTERFACE2}