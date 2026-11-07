#!/usr/bin/env bash
#
# Minecraft Bedrock Dedicated Server installer/manager (Termux Edition)
#
# Install:
#   chmod +x install-bedrock.sh
#   ./install-bedrock.sh install
#
# Perintah:
#   install | start | stop | restart | status | logs | update | backup
#
set -Eeuo pipefail

APP_NAME="Minecraft Bedrock Dedicated Server (Termux)"
SERVER_DIR="${HOME}/bedrock"
BACKUP_DIR="${HOME}/bedrock-backups"
PID_FILE="${SERVER_DIR}/bedrock.pid"
LOG_FILE="${SERVER_DIR}/bedrock.log"
OFFICIAL_PAGE="https://www.minecraft.net/en-us/download/server/bedrock"
DOWNLOAD_BASE="https://www.minecraft.net/bedrockdedicatedserver/bin-linux"

SERVER_PORT="${SERVER_PORT:-19132}"
SERVER_PORT_V6="${SERVER_PORT_V6:-19133}"
MAX_PLAYERS="${MAX_PLAYERS:-10}"
SERVER_NAME="${SERVER_NAME:-Bedrock Dedicated Server}"
GAMEMODE="${GAMEMODE:-survival}"
DIFFICULTY="${DIFFICULTY:-normal}"
LEVEL_NAME="${LEVEL_NAME:-Bedrock level}"

log()  { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

check_platform() {
  local arch
  arch="$(uname -m)"
  log "Mendeteksi arsitektur perangkat: ${arch}"
  if [[ "${arch}" != "x86_64" && "${arch}" != "aarch64" ]]; then
    die "Arsitektur tidak didukung: ${arch}. BDS resmi membutuhkan x86_64 atau ARM64 dengan emulator."
  fi
  if [[ "${arch}" == "aarch64" ]]; then
    warn "Perangkat Android Anda menggunakan arsitektur ARM64."
    warn "Binary BDS resmi dikompilasi untuk x86_64, sehingga membutuhkan emulator (seperti qemu-user-x86_64 atau box64)."
  fi
}

install_packages() {
  log "Memasang dependensi Termux..."
  pkg update -y
  pkg install -y ca-certificates curl unzip python libcurl

  local arch
  arch="$(uname -m)"
  if [[ "${arch}" == "aarch64" ]]; then
    if ! command -v qemu-x86_64 >/dev/null 2>&1 && ! command -v box64 >/dev/null 2>&1; then
      log "Mencoba memasang qemu-user-x86_64 untuk menjalankan binary x86_64..."
      pkg install -y qemu-user-x86_64 || warn "Tidak dapat memasang qemu-user-x86_64 otomatis. Jika server tidak bisa berjalan, pasang box64 atau qemu-user-x86_64 secara manual."
    fi
  fi
}

ensure_dirs() {
  mkdir -p "${SERVER_DIR}"
  mkdir -p "${BACKUP_DIR}"
}

latest_download_url() {
  local html version
  html="$(mktemp)"
  if ! curl -fL --retry 3 --connect-timeout 20 "${OFFICIAL_PAGE}" -o "${html}"; then
    rm -f "${html}"
    die "Tidak bisa mengambil halaman download resmi Minecraft."
  fi

  version="$(python - "${html}" <<'PY'
import re, sys
data = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
data = data.replace("\\/", "/")
matches = re.findall(
    r"(?:https?://www\.minecraft\.net)?/bedrockdedicatedserver/bin-linux/bedrock-server-([0-9][0-9.]*)\.zip",
    data,
)
if matches:
    print(matches[-1])
PY
)"
  rm -f "${html}"

  if [[ -z "${version}" ]]; then
    die "Tidak berhasil mendeteksi versi Linux stabil dari halaman resmi."
  fi
  printf '%s/%s\n' "${DOWNLOAD_BASE}" "bedrock-server-${version}.zip"
}

download_and_extract() {
  local url="$1" target="$2"
  local zipfile
  zipfile="$(mktemp --suffix=.zip)"
  log "Mengunduh paket resmi: ${url}"
  curl -fL --retry 3 --connect-timeout 20 "${url}" -o "${zipfile}"
  unzip -tq "${zipfile}" >/dev/null || { rm -f "${zipfile}"; die "Arsip ZIP rusak/tidak valid."; }
  mkdir -p "${target}"
  unzip -oq "${zipfile}" -d "${target}"
  rm -f "${zipfile}"
  [[ -f "${target}/bedrock_server" ]] || die "File bedrock_server tidak ditemukan di arsip."
  chmod 0755 "${target}/bedrock_server"
}

write_default_config() {
  local config="${SERVER_DIR}/server.properties"
  if [[ ! -f "${config}" ]]; then
    cat > "${config}" <<EOF
server-name=${SERVER_NAME}
gamemode=${GAMEMODE}
force-gamemode=false
difficulty=${DIFFICULTY}
allow-cheats=false
max-players=${MAX_PLAYERS}
online-mode=true
allow-list=false
server-port=${SERVER_PORT}
server-portv6=${SERVER_PORT_V6}
view-distance=16
tick-distance=4
player-idle-timeout=30
max-threads=8
level-name=${LEVEL_NAME}
level-seed=
default-player-permission-level=member
texturepack-required=false
EOF
  fi
}

get_exec_cmd() {
  local arch
  arch="$(uname -m)"
  if [[ "${arch}" == "aarch64" ]]; then
    if command -v box64 >/dev/null 2>&1; then
      echo "box64 ./bedrock_server"
    elif command -v qemu-x86_64 >/dev/null 2>&1; then
      echo "qemu-x86_64 ./bedrock_server"
    else
      echo "./bedrock_server"
    fi
  else
    echo "./bedrock_server"
  fi
}

is_running() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

start_server() {
  if is_running; then
    warn "Server sudah berjalan (PID: $(cat "${PID_FILE}"))."
    return 0
  fi

  [[ -x "${SERVER_DIR}/bedrock_server" ]] || die "Server belum terpasang. Jalankan '$0 install'."

  log "Menjalankan Minecraft Bedrock Server di background..."
  cd "${SERVER_DIR}"

  local exec_cmd
  exec_cmd="$(get_exec_cmd)"

  export LD_LIBRARY_PATH="${SERVER_DIR}:${LD_LIBRARY_PATH:-}"

  nohup ${exec_cmd} > "${LOG_FILE}" 2>&1 &
  local pid=$!
  echo "${pid}" > "${PID_FILE}"

  sleep 2
  if kill -0 "${pid}" 2>/dev/null; then
    log "Server berhasil dijalankan (PID: ${pid})."
    log "Log dapat dilihat dengan: $0 logs"
  else
    warn "Server gagal berjalan. Periksa log dengan: $0 logs"
  fi
}

stop_server() {
  if ! is_running; then
    warn "Server sedang tidak berjalan."
    rm -f "${PID_FILE}" 2>/dev/null || true
    return 0
  fi

  local pid
  pid="$(cat "${PID_FILE}")"
  log "Menghentikan server (PID: ${pid})..."
  kill -15 "${pid}" 2>/dev/null || true

  local count=0
  while kill -0 "${pid}" 2>/dev/null; do
    sleep 1
    count=$((count + 1))
    if [[ ${count} -ge 30 ]]; then
      warn "Server tidak merespons SIGTERM, menghentikan paksa (SIGKILL)..."
      kill -9 "${pid}" 2>/dev/null || true
      break
    fi
  done

  rm -f "${PID_FILE}"
  log "Server telah dihentikan."
}

restart_server() {
  log "Merestart server..."
  stop_server
  sleep 1
  start_server
}

status_server() {
  if is_running; then
    log "Status: BERJALAN (PID: $(cat "${PID_FILE}"))"
  else
    log "Status: MATI"
  fi
}

logs_server() {
  if [[ ! -f "${LOG_FILE}" ]]; then
    die "File log belum ada: ${LOG_FILE}"
  fi
  log "Menampilkan log (Tekan Ctrl+C untuk keluar)..."
  tail -n 100 -f "${LOG_FILE}"
}

backup_server() {
  [[ -d "${SERVER_DIR}" ]] || die "Direktori server tidak ditemukan: ${SERVER_DIR}"
  ensure_dirs
  local stamp archive
  stamp="$(date +%Y%m%d-%H%M%S)"
  archive="${BACKUP_DIR}/bedrock-${stamp}.tar.gz"
  log "Membuat backup ke ${archive}..."
  tar -czf "${archive}" -C "$(dirname "${SERVER_DIR}")" "$(basename "${SERVER_DIR}")"
  log "Backup selesai: ${archive}"
}

install_server() {
  check_platform
  install_packages
  ensure_dirs

  if [[ -x "${SERVER_DIR}/bedrock_server" ]]; then
    die "Instalasi BDS sudah ada di ${SERVER_DIR}. Gunakan '$0 update' untuk memperbarui."
  fi

  local url staging
  url="$(latest_download_url)"
  staging="$(mktemp -d)"
  trap 'rm -rf "${staging}"' RETURN
  download_and_extract "${url}" "${staging}"
  cp -a "${staging}/." "${SERVER_DIR}/"
  write_default_config
  chmod 0755 "${SERVER_DIR}/bedrock_server"

  start_server
  show_summary
}

update_server() {
  check_platform
  [[ -x "${SERVER_DIR}/bedrock_server" ]] || die "BDS belum terpasang. Jalankan '$0 install'."

  local url staging preserve
  url="$(latest_download_url)"
  staging="$(mktemp -d)"
  preserve="$(mktemp -d)"
  trap 'rm -rf "${staging}" "${preserve}"' RETURN

  backup_server
  stop_server || true

  for item in worlds server.properties allowlist.json permissions.json \
              whitelist.json valid_known_packs.json resource_packs behavior_packs; do
    if [[ -e "${SERVER_DIR}/${item}" ]]; then
      cp -a "${SERVER_DIR}/${item}" "${preserve}/"
    fi
  done

  if ! download_and_extract "${url}" "${staging}"; then
    start_server || true
    die "Update gagal diunduh/diekstrak; server dicoba dinyalakan kembali."
  fi

  cp -a "${staging}/." "${SERVER_DIR}/"
  cp -a "${preserve}/." "${SERVER_DIR}/"
  chmod 0755 "${SERVER_DIR}/bedrock_server"
  start_server
}

show_summary() {
  printf '\n%s\n' "----- ${APP_NAME} -----"
  printf 'Direktori : %s\n' "${SERVER_DIR}"
  printf 'Port      : UDP %s (IPv4), UDP %s (IPv6)\n' "${SERVER_PORT}" "${SERVER_PORT_V6}"
  printf 'Status    : '
  if is_running; then printf 'Aktif (PID %s)\n' "$(cat "${PID_FILE}")"; else printf 'Tidak Aktif\n'; fi
  printf '\nPerintah:\n'
  printf '  %s start\n' "$0"
  printf '  %s stop\n' "$0"
  printf '  %s restart\n' "$0"
  printf '  %s status\n' "$0"
  printf '  %s logs\n' "$0"
  printf '  %s update\n' "$0"
  printf '  %s backup\n\n' "$0"
}

main() {
  local command="${1:-install}"
  case "${command}" in
    install)  install_server ;;
    start)    start_server ;;
    stop)     stop_server ;;
    restart)  restart_server ;;
    status)   status_server ;;
    logs)     logs_server ;;
    update)   update_server ;;
    backup)   backup_server ;;
    help|-h|--help)
      sed -n '2,11p' "$0"
      ;;
    *) die "Perintah tidak dikenal: ${command}. Gunakan: install|start|stop|restart|status|logs|update|backup" ;;
  esac
}
main "$@"
