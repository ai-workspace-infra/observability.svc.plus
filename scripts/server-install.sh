#!/bin/bash
#==============================================================#
# File      : server-install.sh
# Mtime     : 2026-02-03
# Desc      : observability.svc.plus lifecycle installer
# Usage     : curl ... | bash -s -- [options] [VERSION] [DOMAIN]
#==============================================================#

set -euo pipefail

VERSION="main"
DOMAIN="$(hostname)"
ACTION="deploy"
AUTO_YES=false
FORCE_RECLONE=false
SKIP_DEPLOY=false

REPO_URL="https://github.com/cloud-neutral-toolkit/observability.svc.plus.git"
REPO_NAME="$(basename "${REPO_URL}" .git)"
INSTALL_DIR="${HOME}/${REPO_NAME}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

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

domain_points_to_local_host() {
    local host="$1"
    local local_ip
    local resolved_ip
    local local_ips=()
    local resolved_ips=()

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
  bash server-install.sh [options] [VERSION] [DOMAIN]
  bash server-install.sh [options] [DOMAIN]

Actions (default: deploy):
  --action deploy     Deploy or upgrade in place (idempotent)
  --action upgrade    Same as deploy
  --action reset      Rebuild from scratch (destructive)
  --action uninstall  Remove install dir and local systemd units

Options:
  -y, --yes           Non-interactive mode
  --force-reclone     Re-clone repo before deploy/upgrade
  --skip-deploy       Only sync repo/bootstrap/configure, skip deploy.yml
  -h, --help          Show help

Examples:
  curl -fsSL ".../server-install.sh" | bash -s -- observability.svc.plus
  curl -fsSL ".../server-install.sh" | bash -s -- --action upgrade observability.svc.plus
  curl -fsSL ".../server-install.sh" | bash -s -- --action reset -y observability.svc.plus

Notes:
  DOMAIN is the public ingress domain. The current machine may still be named
  us-xhttp.svc.plus while serving traffic for observability.svc.plus.
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

ensure_repo() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "git is not installed."
        exit 1
    fi

    if [[ ! -d "${INSTALL_DIR}/.git" || "${FORCE_RECLONE}" == "true" ]]; then
        if [[ -d "${INSTALL_DIR}" ]]; then
            log_warn "Removing existing directory before clone: ${INSTALL_DIR}"
            rm -rf "${INSTALL_DIR}"
        fi
        log_info "Cloning ${REPO_URL} (${VERSION}) ..."
        git clone -b "${VERSION}" "${REPO_URL}" "${INSTALL_DIR}"
    else
        log_info "Updating existing repo at ${INSTALL_DIR}"
        git -C "${INSTALL_DIR}" fetch --prune origin
        git -C "${INSTALL_DIR}" checkout "${VERSION}"
        git -C "${INSTALL_DIR}" pull --ff-only origin "${VERSION}"
    fi
}

ensure_root_ssh_access() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return 0
    fi

    log_info "Ensuring root SSH key-based access..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N "" -q
    fi

    local public_key
    public_key="$(cat ~/.ssh/id_rsa.pub)"
    touch ~/.ssh/authorized_keys
    if ! grep -qF "${public_key}" ~/.ssh/authorized_keys; then
        echo "${public_key}" >> ~/.ssh/authorized_keys
    fi
    chmod 600 ~/.ssh/authorized_keys

    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
            sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
        elif ! grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config; then
            echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
        fi
        systemctl reload ssh >/dev/null 2>&1 || systemctl reload sshd >/dev/null 2>&1 || true
    fi
}

run_bootstrap() {
    cd "${INSTALL_DIR}"
    if [[ -x "./bootstrap" ]]; then
        log_info "Running bootstrap..."
        ./bootstrap
    elif [[ -f "./configure" ]]; then
        log_info "No bootstrap found, proceeding with configure."
    else
        log_error "Neither bootstrap nor configure exists in ${INSTALL_DIR}"
        exit 1
    fi
}

run_configure() {
    cd "${INSTALL_DIR}"
    if [[ -x "./configure" ]]; then
        log_info "Running configure..."
        ./configure -n -i 127.0.0.1
    fi
    if [[ -f "pigsty.yml" ]]; then
        log_info "Tuning pigsty.yml: setting 127.0.0.1 and enabling Caddy..."
        sed -i 's/10\.146\.0\.6/127.0.0.1/g' pigsty.yml
        
        # Ensure Nginx is disabled and Caddy is enabled in global vars
        # We look for the 'vars:' section under 'all:'
        if grep -q "nginx_enabled:" pigsty.yml; then
            sed -i 's/nginx_enabled: .*/nginx_enabled: false/' pigsty.yml
        else
            sed -i '/vars:/a \    nginx_enabled: false' pigsty.yml
        fi

        if grep -q "caddy_enabled:" pigsty.yml; then
            sed -i 's/caddy_enabled: .*/caddy_enabled: true/' pigsty.yml
        else
            sed -i '/vars:/a \    caddy_enabled: true' pigsty.yml
        fi

        if grep -q "infra_domain:" pigsty.yml; then
            sed -i -E "s#^([[:space:]]*infra_domain:).*#\\1 ${DOMAIN}#" pigsty.yml
        else
            sed -i "/caddy_enabled:/a\\    infra_domain: ${DOMAIN}" pigsty.yml
        fi

        if grep -qE '^([[:space:]]*)home[[:space:]]*:[[:space:]]*\{[[:space:]]*domain:' pigsty.yml; then
            sed -i -E "s#^([[:space:]]*home[[:space:]]*:[[:space:]]*\\{[[:space:]]*domain:[[:space:]]*)[^,}]+(.*)#\\1${DOMAIN}\\2#" pigsty.yml
        fi
    fi
}

check_dns_preflight() {
    if domain_points_to_local_host "${DOMAIN}"; then
        log_ok "DNS preflight passed: ${DOMAIN} resolves to this host."
        return 0
    fi

    log_warn "DNS preflight: ${DOMAIN} does not currently resolve to this host."
    log_warn "Recommended order: update DNS first, then deploy the server on this machine."
}

run_deploy() {
    cd "${INSTALL_DIR}"
    if [[ "${SKIP_DEPLOY}" == "true" ]]; then
        log_warn "Skipping deploy.yml as requested."
        return 0
    fi
    if [[ -x "./deploy.yml" ]]; then
        log_info "Running deploy.yml ..."
        ./deploy.yml
    else
        log_warn "deploy.yml not found, skipping."
    fi
}

configure_ingest_gateway() {
    local home_conf="/etc/nginx/conf.d/home.conf"
    local ingest_inc="/etc/nginx/conf.d/ingest-observability.inc"

    if [[ -f "${home_conf}" ]]; then
        log_info "Configuring HTTPS ingest routes in nginx..."
        cat > "${ingest_inc}" <<'EOF'
# managed by scripts/server-install.sh
location = /ingest/metrics/api/v1/write {
    proxy_pass http://127.0.0.1:8428/api/v1/write;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location = /ingest/logs/insert/loki/api/v1/push {
    proxy_pass http://127.0.0.1:9428/insert/loki/api/v1/push;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location = /ingest/otlp/v1/traces {
    proxy_pass http://127.0.0.1:10428/insert/opentelemetry/v1/traces;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
EOF

        if ! grep -q "include /etc/nginx/conf.d/ingest-observability.inc;" "${home_conf}"; then
            # Keep it near top-level server directives so location blocks are active.
            sed -i '/proxy_request_buffering off;/a\    include /etc/nginx/conf.d/ingest-observability.inc;' "${home_conf}"
        fi

        nginx -t
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
        else
            log_warn "nginx is inactive, skip reload."
        fi
        log_ok "Nginx ingest gateway configured."
    else
        log_warn "Nginx home.conf not found, skipping nginx ingest config."
    fi

    if [[ -f "/etc/caddy/Caddyfile" ]]; then
        log_info "Configuring ingest reverse proxy in caddy..."
        sed -i -E 's|(reverse_proxy[[:space:]]+)127\\.0\\.0\\.1:12345|\\1127.0.0.1:8428|g' /etc/caddy/Caddyfile
        sed -i -E 's|(reverse_proxy[[:space:]]+)127\\.0\\.0\\.1:12346|\\1127.0.0.1:9428|g' /etc/caddy/Caddyfile
        if command -v caddy >/dev/null 2>&1; then
            caddy validate --config /etc/caddy/Caddyfile
        fi
        if systemctl is-active --quiet caddy; then
            systemctl reload caddy
        fi
        log_ok "Caddy ingest gateway configured."
    fi
}

uninstall_stack() {
    log_warn "Uninstall action will remove local install assets."
    confirm "Continue uninstall?" || { log_info "Cancelled."; return 0; }

    if [[ -d "${INSTALL_DIR}" ]]; then
        rm -rf "${INSTALL_DIR}"
        log_ok "Removed ${INSTALL_DIR}"
    else
        log_info "Install directory does not exist: ${INSTALL_DIR}"
    fi

    for unit in pigsty vmetrics vlogs vtraces grafana-server; do
        if systemctl list-unit-files | grep -q "^${unit}\.service"; then
            systemctl disable --now "${unit}" >/dev/null 2>&1 || true
            rm -f "/etc/systemd/system/${unit}.service"
        fi
    done
    systemctl daemon-reload
    log_ok "Uninstall cleanup finished."
}

deploy_or_upgrade() {
    log_info "Cleaning up potential port conflicts (80/443)..."
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 80/tcp 443/tcp || true
    fi
    systemctl stop nginx apache2 caddy 2>/dev/null || true

    ensure_repo
    ensure_root_ssh_access
    check_dns_preflight
    run_bootstrap
    run_configure
    run_deploy
    configure_ingest_gateway

    log_ok "Deploy/upgrade completed."
    echo -e "----------------------------------------------------------------"
    echo -e "Dashboard       : https://${DOMAIN}"
    echo -e "user            : admin"
    echo -e "Pass            : pigsty"
    echo -e "----------------------------------------------------------------"
    echo -e "Metrics Ingest  : https://${DOMAIN}/ingest/metrics/api/v1/write"
    echo -e "Logs Ingest     : https://${DOMAIN}/ingest/logs/insert"
    echo -e "Traces Ingest   : https://${DOMAIN}/ingest/otlp/v1/traces"
    echo -e "PromQL Query    : http://${DOMAIN}:8428/api/v1/query"
    echo -e "Remote Write    : http://${DOMAIN}:8428/api/v1/write"
    echo -e "Grafana         : https://${DOMAIN}/grafana"
    echo -e "----------------------------------------------------------------"
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
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --force-reclone)
            FORCE_RECLONE=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ge 1 ]]; then
    if [[ "$1" == "main" || "$1" == "master" || "$1" == v[0-9]* ]]; then
        VERSION="$1"
        DOMAIN="${2:-$(hostname)}"
    else
        DOMAIN="$1"
    fi
fi

log_info "Repo    : ${REPO_URL}"
log_info "Dir     : ${INSTALL_DIR}"
log_info "Version : ${VERSION}"
log_info "Domain  : ${DOMAIN}"
log_info "Action  : ${ACTION}"

case "${ACTION}" in
    deploy|upgrade)
        deploy_or_upgrade
        ;;
    reset)
        confirm "Reset will remove and reinstall ${INSTALL_DIR}. Continue?" || {
            log_info "Cancelled."
            exit 0
        }
        FORCE_RECLONE=true
        deploy_or_upgrade
        ;;
    uninstall)
        uninstall_stack
        ;;
    *)
        log_error "Unsupported action: ${ACTION}"
        usage
        exit 1
        ;;
esac
