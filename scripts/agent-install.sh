#!/bin/bash
set -euo pipefail

DEFAULT_ENDPOINT="https://observability.svc.plus/ingest/otlp"
INSTALL_DIR="/opt/observability"
BIN_DIR="${INSTALL_DIR}/bin"
CONFIG_DIR="${INSTALL_DIR}/config"
DATA_DIR="${INSTALL_DIR}/data"

NODE_EXPORTER_VERSION="1.7.0"
PROCESS_EXPORTER_VERSION="0.7.10"
VECTOR_VERSION="0.36.0"

ACTION="deploy"
ENDPOINT="${DEFAULT_ENDPOINT}"
METRICS_ENDPOINT=""
LOGS_ENDPOINT=""
METRICS_ENDPOINT_SET=false
LOGS_ENDPOINT_SET=false
DEEPFLOW_AGENT_ENABLED=false
DEEPFLOW_GRPC_ENDPOINT=""
DEEPFLOW_AGENT_ENDPOINT_ARG="--grpc-server"
DEEPFLOW_AGENT_DOWNLOAD_URL=""
DEEPFLOW_AGENT_BIN="${BIN_DIR}/deepflow-agent"
AUTO_YES=false

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

append_unique() {
    local value="$1"
    local -n target_ref="$2"
    [[ -z "${value}" ]] && return 0
    local existing
    for existing in "${target_ref[@]:-}"; do
        if [[ "${existing}" == "${value}" ]]; then
            return 0
        fi
    done
    target_ref+=("${value}")
}

collect_local_ipv4s() {
    local ips=()
    local ip

    if command -v hostname >/dev/null 2>&1; then
        for ip in $(hostname -I 2>/dev/null || true); do
            append_unique "${ip}" ips
        done
    fi

    if command -v ip >/dev/null 2>&1; then
        while read -r ip; do
            append_unique "${ip}" ips
        done < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    fi

    printf '%s\n' "${ips[@]}"
}

resolve_ipv4s() {
    local host="$1"
    local ips=()
    local ip

    if command -v getent >/dev/null 2>&1; then
        while read -r ip _; do
            append_unique "${ip}" ips
        done < <(getent ahostsv4 "${host}" 2>/dev/null || true)
    fi

    if [[ ${#ips[@]} -eq 0 ]] && command -v host >/dev/null 2>&1; then
        while read -r ip; do
            append_unique "${ip}" ips
        done < <(host "${host}" 2>/dev/null | awk '/has address/ {print $4}')
    fi

    printf '%s\n' "${ips[@]}"
}

extract_host_from_url() {
    local url="$1"
    url="${url#*://}"
    url="${url%%/*}"
    url="${url%%:*}"
    printf '%s\n' "${url}"
}

endpoint_targets_local_host() {
    local host="$1"
    local local_host
    local local_short
    local local_ip
    local resolved_ip
    local local_ips=()
    local resolved_ips=()

    local_host="$(hostname -f 2>/dev/null || hostname)"
    local_short="${local_host%%.*}"
    if [[ "${host}" == "${local_host}" || "${host}" == "${local_short}" ]]; then
        return 0
    fi

    while read -r local_ip; do
        append_unique "${local_ip}" local_ips
    done < <(collect_local_ipv4s)

    while read -r resolved_ip; do
        append_unique "${resolved_ip}" resolved_ips
    done < <(resolve_ipv4s "${host}")

    [[ ${#local_ips[@]} -eq 0 || ${#resolved_ips[@]} -eq 0 ]] && return 1

    for resolved_ip in "${resolved_ips[@]}"; do
        for local_ip in "${local_ips[@]}"; do
            if [[ "${resolved_ip}" == "${local_ip}" ]]; then
                return 0
            fi
        done
    done

    return 1
}

usage() {
    cat <<EOF
Usage:
  bash agent-install.sh [options]

Actions (default: deploy):
  --action deploy     Deploy or upgrade components
  --action upgrade    Alias of deploy
  --action reset      Uninstall then reinstall components
  --action uninstall  Remove agent components

Options:
  --endpoint URL      Base ingest endpoint (default: ${DEFAULT_ENDPOINT})
  --metrics-endpoint URL  Prometheus remote_write endpoint (optional override)
  --logs-endpoint URL     Loki push endpoint (optional override)
  --deepflow-agent        Install and enable deepflow-agent service
  --deepflow-grpc-endpoint HOST:PORT  DeepFlow gRPC endpoint (required if --deepflow-agent)
  --deepflow-agent-endpoint-arg ARG   deepflow-agent endpoint arg (default: ${DEEPFLOW_AGENT_ENDPOINT_ARG})
  --deepflow-agent-download-url URL   Download deepflow-agent binary to ${DEEPFLOW_AGENT_BIN}
  --deepflow-agent-bin PATH           Use existing deepflow-agent binary path
  -y, --yes           Non-interactive mode
  -h, --help          Show help

Example:
  curl -fsSL .../agent-install.sh | bash -s -- --endpoint https://observability.svc.plus/ingest/otlp
EOF
}

confirm() {
    local prompt="$1"
    if [[ "${AUTO_YES}" == "true" ]]; then
        return 0
    fi
    read -r -p "${prompt} [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --action=*)
            ACTION="${1#*=}"
            shift
            ;;
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --endpoint=*)
            ENDPOINT="${1#*=}"
            shift
            ;;
        --metrics-endpoint)
            METRICS_ENDPOINT="$2"
            METRICS_ENDPOINT_SET=true
            shift 2
            ;;
        --metrics-endpoint=*)
            METRICS_ENDPOINT="${1#*=}"
            METRICS_ENDPOINT_SET=true
            shift
            ;;
        --logs-endpoint)
            LOGS_ENDPOINT="$2"
            LOGS_ENDPOINT_SET=true
            shift 2
            ;;
        --logs-endpoint=*)
            LOGS_ENDPOINT="${1#*=}"
            LOGS_ENDPOINT_SET=true
            shift
            ;;
        --deepflow-agent)
            DEEPFLOW_AGENT_ENABLED=true
            shift
            ;;
        --deepflow-grpc-endpoint)
            DEEPFLOW_GRPC_ENDPOINT="$2"
            shift 2
            ;;
        --deepflow-grpc-endpoint=*)
            DEEPFLOW_GRPC_ENDPOINT="${1#*=}"
            shift
            ;;
        --deepflow-agent-endpoint-arg)
            DEEPFLOW_AGENT_ENDPOINT_ARG="$2"
            shift 2
            ;;
        --deepflow-agent-endpoint-arg=*)
            DEEPFLOW_AGENT_ENDPOINT_ARG="${1#*=}"
            shift
            ;;
        --deepflow-agent-download-url)
            DEEPFLOW_AGENT_DOWNLOAD_URL="$2"
            shift 2
            ;;
        --deepflow-agent-download-url=*)
            DEEPFLOW_AGENT_DOWNLOAD_URL="${1#*=}"
            shift
            ;;
        --deepflow-agent-bin)
            DEEPFLOW_AGENT_BIN="$2"
            shift 2
            ;;
        --deepflow-agent-bin=*)
            DEEPFLOW_AGENT_BIN="${1#*=}"
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

base_endpoint="${ENDPOINT%/}"
if [[ "${base_endpoint}" == */ingest/otlp* ]]; then
    base_endpoint="${base_endpoint%%/ingest/otlp*}"
fi
if [[ -z "${METRICS_ENDPOINT}" ]]; then
    METRICS_ENDPOINT="${base_endpoint}/ingest/metrics/api/v1/write"
fi
if [[ -z "${LOGS_ENDPOINT}" ]]; then
    LOGS_ENDPOINT="${base_endpoint}/ingest/logs/insert"
fi
if [[ "${DEEPFLOW_AGENT_ENABLED}" == "true" && -z "${DEEPFLOW_GRPC_ENDPOINT}" ]]; then
    DEEPFLOW_GRPC_ENDPOINT="deepflow-agent.${base_endpoint#*://}:443"
fi

collector_host="$(extract_host_from_url "${base_endpoint}")"
if endpoint_targets_local_host "${collector_host}"; then
    log_info "Collector endpoint resolves to this host; using local ingest ports for self-monitoring."
    if [[ "${METRICS_ENDPOINT_SET}" == "false" ]]; then
        METRICS_ENDPOINT="http://127.0.0.1:8428/api/v1/write"
    fi
    if [[ "${LOGS_ENDPOINT_SET}" == "false" ]]; then
        LOGS_ENDPOINT="http://127.0.0.1:9428/insert"
    fi
fi

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)
        ARCH_NODE="amd64"
        ARCH_PROCESS="amd64"
        ARCH_VECTOR="x86_64"
        ;;
    aarch64|arm64)
        ARCH_NODE="arm64"
        ARCH_PROCESS="arm64"
        ARCH_VECTOR="aarch64"
        ;;
    *)
        log_error "Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

mkdir -p "${BIN_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${DATA_DIR}/vector"

version_from_bin() {
    local bin="$1"
    local regex="$2"
    if [[ ! -x "${bin}" ]]; then
        # With `set -e`, a non-zero exit inside command substitution would abort the script.
        # Missing binaries are expected on first install, so return empty + success.
        echo ""
        return 0
    fi
    "${bin}" --version 2>/dev/null | grep -Eo "${regex}" | head -n1 || true
}

write_unit_if_changed() {
    local unit_name="$1"
    local content="$2"
    local unit_path="/etc/systemd/system/${unit_name}.service"
    local tmp_file
    tmp_file="$(mktemp)"
    printf "%s\n" "${content}" > "${tmp_file}"
    if [[ ! -f "${unit_path}" ]] || ! cmp -s "${tmp_file}" "${unit_path}"; then
        install -m 0644 "${tmp_file}" "${unit_path}"
        systemctl daemon-reload
    fi
    rm -f "${tmp_file}"
}

download_tar_binary() {
    local url="$1"
    local archive_name="$2"
    local source_binary_relpath="$3"
    local target_binary="$4"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fL --progress-bar "${url}" -o "${tmp_dir}/${archive_name}"
    tar -xzf "${tmp_dir}/${archive_name}" -C "${tmp_dir}"
    install -m 0755 "${tmp_dir}/${source_binary_relpath}" "${target_binary}"
    rm -rf "${tmp_dir}"
}

install_node_exporter() {
    local current_version
    current_version="$(version_from_bin "${BIN_DIR}/node_exporter" '[0-9]+\.[0-9]+\.[0-9]+')"
    if [[ "${current_version}" != "${NODE_EXPORTER_VERSION}" ]]; then
        log_info "Installing Node Exporter v${NODE_EXPORTER_VERSION} (current: ${current_version:-none})"
        download_tar_binary \
            "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH_NODE}.tar.gz" \
            "node_exporter.tar.gz" \
            "node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH_NODE}/node_exporter" \
            "${BIN_DIR}/node_exporter"
    else
        log_info "Node Exporter already at desired version ${NODE_EXPORTER_VERSION}"
    fi

    write_unit_if_changed "node_exporter" "[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=${BIN_DIR}/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target"

    systemctl enable --now node_exporter
    systemctl restart node_exporter
}

install_process_exporter() {
    local current_version
    current_version="$(version_from_bin "${BIN_DIR}/process-exporter" '[0-9]+\.[0-9]+\.[0-9]+')"
    if [[ "${current_version}" != "${PROCESS_EXPORTER_VERSION}" ]]; then
        log_info "Installing Process Exporter v${PROCESS_EXPORTER_VERSION} (current: ${current_version:-none})"
        download_tar_binary \
            "https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/process-exporter-${PROCESS_EXPORTER_VERSION}.linux-${ARCH_PROCESS}.tar.gz" \
            "process_exporter.tar.gz" \
            "process-exporter-${PROCESS_EXPORTER_VERSION}.linux-${ARCH_PROCESS}/process-exporter" \
            "${BIN_DIR}/process-exporter"
    else
        log_info "Process Exporter already at desired version ${PROCESS_EXPORTER_VERSION}"
    fi

    cat <<EOF > "${CONFIG_DIR}/process-config.yaml"
process_names:
  - name: "{{.Comm}}"
    cmdline:
      - '.+'
EOF

    write_unit_if_changed "process_exporter" "[Unit]
Description=Process Exporter
After=network.target

[Service]
User=root
ExecStart=${BIN_DIR}/process-exporter -config.path ${CONFIG_DIR}/process-config.yaml
Restart=always

[Install]
WantedBy=multi-user.target"

    systemctl enable --now process_exporter
    systemctl restart process_exporter
}

write_vector_config() {
    cat <<EOF > "${CONFIG_DIR}/vector.yaml"
data_dir: "${DATA_DIR}/vector"

sources:
  node_exporter:
    type: prometheus_scrape
    endpoints:
      - http://127.0.0.1:9100/metrics
    scrape_interval_secs: 15

  process_exporter:
    type: prometheus_scrape
    endpoints:
      - http://127.0.0.1:9256/metrics
    scrape_interval_secs: 15

  journald:
    type: journald
    current_boot_only: true

  syslog_files:
    type: file
    include:
      - /var/log/syslog
      - /var/log/messages
      - /var/log/auth.log
    read_from: end

transforms:
  add_metric_labels:
    type: remap
    inputs: ["node_exporter", "process_exporter"]
    source: |
      .tags.host = get_hostname!()
      .tags.job = "node"
      .tags.origin = "vector-agent"

  add_log_labels:
    type: remap
    inputs: ["journald", "syslog_files"]
    source: |
      .host = get_hostname!()
      .job = "node"
      .origin = "vector-agent"
      .timestamp = now()

sinks:
  metrics_out:
    type: prometheus_remote_write
    inputs: ["add_metric_labels"]
    endpoint: "${METRICS_ENDPOINT}"
    compression: snappy
    healthcheck: false

  logs_out:
    type: loki
    inputs: ["add_log_labels"]
    endpoint: "${LOGS_ENDPOINT}"
    compression: gzip
    encoding:
      codec: json
    labels:
      host: "{{ host }}"
      job: "{{ job }}"
      origin: "{{ origin }}"
EOF
}

install_vector() {
    local current_version
    current_version="$(version_from_bin "${BIN_DIR}/vector" '[0-9]+\.[0-9]+\.[0-9]+')"
    if [[ "${current_version}" != "${VECTOR_VERSION}" ]]; then
        log_info "Installing Vector v${VECTOR_VERSION} (current: ${current_version:-none})"
        download_tar_binary \
            "https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH_VECTOR}-unknown-linux-gnu.tar.gz" \
            "vector.tar.gz" \
            "vector-${ARCH_VECTOR}-unknown-linux-gnu/bin/vector" \
            "${BIN_DIR}/vector"
    else
        log_info "Vector already at desired version ${VECTOR_VERSION}"
    fi

    write_vector_config
    if ! "${BIN_DIR}/vector" validate --no-environment --config-yaml "${CONFIG_DIR}/vector.yaml" >/dev/null 2>&1; then
        log_error "Vector config validation failed."
        "${BIN_DIR}/vector" validate --no-environment --config-yaml "${CONFIG_DIR}/vector.yaml" || true
        exit 1
    fi

    write_unit_if_changed "vector" "[Unit]
Description=Vector
Documentation=https://vector.dev
After=network-online.target
Requires=network-online.target

[Service]
User=root
ExecStart=${BIN_DIR}/vector --config ${CONFIG_DIR}/vector.yaml
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=VECTOR_LOG=info

[Install]
WantedBy=multi-user.target"

    systemctl enable --now vector
    systemctl restart vector
}

install_deepflow_agent() {
    if [[ "${DEEPFLOW_AGENT_ENABLED}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${DEEPFLOW_GRPC_ENDPOINT}" ]]; then
        log_error "DeepFlow agent enabled but --deepflow-grpc-endpoint is empty."
        exit 1
    fi

    if [[ -n "${DEEPFLOW_AGENT_DOWNLOAD_URL}" ]]; then
        log_info "Downloading deepflow-agent binary..."
        curl -fL --progress-bar "${DEEPFLOW_AGENT_DOWNLOAD_URL}" -o "${DEEPFLOW_AGENT_BIN}"
        chmod 0755 "${DEEPFLOW_AGENT_BIN}"
    elif [[ ! -x "${DEEPFLOW_AGENT_BIN}" ]]; then
        if command -v deepflow-agent >/dev/null 2>&1; then
            DEEPFLOW_AGENT_BIN="$(command -v deepflow-agent)"
        else
            log_error "deepflow-agent binary not found. Use --deepflow-agent-download-url or --deepflow-agent-bin."
            exit 1
        fi
    fi

    cat <<EOF > "${CONFIG_DIR}/deepflow-agent.env"
DEEPFLOW_GRPC_ENDPOINT=${DEEPFLOW_GRPC_ENDPOINT}
DEEPFLOW_AGENT_ENDPOINT_ARG=${DEEPFLOW_AGENT_ENDPOINT_ARG}
EOF

    cat <<'EOF' > "${BIN_DIR}/run-deepflow-agent.sh"
#!/bin/bash
set -euo pipefail
: "${DEEPFLOW_AGENT_BIN:?missing DEEPFLOW_AGENT_BIN}"
: "${DEEPFLOW_AGENT_ENDPOINT_ARG:?missing DEEPFLOW_AGENT_ENDPOINT_ARG}"
: "${DEEPFLOW_GRPC_ENDPOINT:?missing DEEPFLOW_GRPC_ENDPOINT}"
exec "${DEEPFLOW_AGENT_BIN}" "${DEEPFLOW_AGENT_ENDPOINT_ARG}" "${DEEPFLOW_GRPC_ENDPOINT}"
EOF
    chmod 0755 "${BIN_DIR}/run-deepflow-agent.sh"

    write_unit_if_changed "deepflow_agent" "[Unit]
Description=DeepFlow Agent
After=network-online.target
Wants=network-online.target

[Service]
User=root
EnvironmentFile=${CONFIG_DIR}/deepflow-agent.env
Environment=DEEPFLOW_AGENT_BIN=${DEEPFLOW_AGENT_BIN}
ExecStart=${BIN_DIR}/run-deepflow-agent.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target"

    systemctl enable --now deepflow_agent
    systemctl restart deepflow_agent
}

uninstall_agent() {
    confirm "This will uninstall observability agent components. Continue?" || {
        log_info "Cancelled."
        return 0
    }

    for svc in deepflow_agent vector process_exporter node_exporter; do
        systemctl disable --now "${svc}" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${svc}.service"
    done
    systemctl daemon-reload
    rm -f "${BIN_DIR}/run-deepflow-agent.sh" "${CONFIG_DIR}/deepflow-agent.env"
    rm -rf "${INSTALL_DIR}"
    log_success "Agent components uninstalled."
}

verify_installation() {
    sleep 2
    log_info "Verifying services..."
    for service in node_exporter process_exporter vector; do
        if systemctl is-active --quiet "${service}"; then
            log_success "Service '${service}' is running"
        else
            log_fail "Service '${service}' is NOT running"
            systemctl status "${service}" --no-pager | head -n 20 || true
        fi
    done
    if [[ "${DEEPFLOW_AGENT_ENABLED}" == "true" ]]; then
        if systemctl is-active --quiet deepflow_agent; then
            log_success "Service 'deepflow_agent' is running"
        else
            log_fail "Service 'deepflow_agent' is NOT running"
            systemctl status deepflow_agent --no-pager | head -n 20 || true
        fi
    fi

    log_info "Checking ports..."
    for item in "9100 Node Exporter" "9256 Process Exporter"; do
        local port name
        port="${item%% *}"
        name="${item#* }"
        if ss -tuln | grep -q ":${port} "; then
            log_success "Port ${port} (${name}) is listening"
        else
            log_fail "Port ${port} (${name}) is NOT listening"
        fi
    done
}

print_endpoint_summary() {
    echo
    log_success "Resolved ingest endpoints:"
    echo "  Base URL         : ${base_endpoint}"
    echo "  Metrics endpoint : ${METRICS_ENDPOINT}"
    echo "  Logs endpoint    : ${LOGS_ENDPOINT}"
}

deploy_agent() {
    log_info "Action=${ACTION}"
    log_info "Base endpoint=${ENDPOINT}"
    log_info "Metrics endpoint=${METRICS_ENDPOINT}"
    log_info "Logs endpoint=${LOGS_ENDPOINT}"
    if [[ "${DEEPFLOW_AGENT_ENABLED}" == "true" ]]; then
        log_info "DeepFlow endpoint=${DEEPFLOW_GRPC_ENDPOINT}"
    fi
    install_node_exporter
    install_process_exporter
    install_vector
    install_deepflow_agent
    verify_installation
    log_success "Agent deploy/upgrade complete."
    print_endpoint_summary
}

case "${ACTION}" in
    deploy|upgrade)
        deploy_agent
        ;;
    reset)
        uninstall_agent
        deploy_agent
        ;;
    uninstall)
        uninstall_agent
        ;;
    *)
        log_error "Unsupported action: ${ACTION}"
        usage
        exit 1
        ;;
esac
