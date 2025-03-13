#!/bin/bash
# Объединённый скрипт установки ASF и FPC для Debian-based систем
# Автор: @mazanO1 (на основе работ exfador, sidor0912 и JustArchiNET)

# Цвета
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
GRAY='\033[90m'
RESET='\033[0m'

log() {
  echo -e "${GRAY}[$(date +%T)]${RESET} $1"
}

info() {
  echo -e "${GREEN}==>${RESET} $1"
}

warn() {
  echo -e "${YELLOW}!WARN!${RESET} $1" >&2
}

error() {
  echo -e "${RED}!!!${RESET} $1" >&2
  exit 1
}

debug() {
  echo -e "${CYAN}DEBUG:${RESET} $1"
}

echo -e "${GREEN}"
echo "Объединённый установщик ASF и FPC для Debian"
echo "Создан @exfador на основе:"
echo "- ArchiSteamFarm от JustArchiNET"
echo "- FunPayCardinal от sidor0912"
echo -e "${RESET}"

# --- Проверка прав ---
if [[ $EUID -ne 0 ]]; then
    warn "Скрипт должен быть запущен с правами root! Используйте sudo."
    exit 1
fi

# --- Шаг 1: Настройка пользователей ---
info "Начинаем процесс установки"
log "Проверка существующих пользователей"

echo -n -e "${YELLOW}Введите имя пользователя для FunPayCardinal (например, 'fpc'): ${RESET}"
while true; do
  read fpc_user
  if [[ "$fpc_user" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
    if id "$fpc_user" &>/dev/null; then
      warn "Пользователь '$fpc_user' уже существует! Выберите другое имя"
    else
      info "Пользователь '$fpc_user' будет создан"
      break
    fi
  else
    warn "Недопустимые символы в имени пользователя"
  fi
done

# --- Шаг 2: Обновление системы и установка зависимостей ---
info "Обновление системы и установка зависимостей"
export DEBIAN_FRONTEND=noninteractive

log "Обновление списка пакетов"
apt update -yq || error "Ошибка при обновлении списка пакетов"

log "Обновление системы"
apt upgrade -yq || error "Ошибка при обновлении пакетов"

info "Установка основных зависимостей"
apt install -yq --no-install-recommends \
  curl \
  unzip \
  screen \
  jq \
  mono-runtime \
  ca-certificates \
  apt-transport-https \
  software-properties-common || error "Ошибка при установке зависимостей"

# Установка libicu в зависимости от версии Debian
debian_version=$(lsb_release -rs)
if [[ "$debian_version" == "12" ]]; then
    apt install -yq libicu72 || error "Ошибка установки libicu72"
elif [[ "$debian_version" == "11" ]]; then
    apt install -yq libicu67 || error "Ошибка установки libicu67"
else
    warn "Неизвестная версия Debian. Установите пакет libicu вручную"
fi

# Проверка наличия Python 3.12
if ! command -v python3.12 &> /dev/null; then
    warn "Python 3.12 не найден. Добавляем репозиторий deadsnakes..."
    add-apt-repository -y ppa:deadsnakes/ppa || error "Ошибка добавления PPA"
    apt update -yq
    apt install -yq python3.12 python3.12-venv || error "Ошибка установки Python 3.12"
fi

# --- Шаг 3: Установка ArchiSteamFarm ---
info "Установка ArchiSteamFarm (ASF)"
log "Создание пользователя 'asf'"
useradd -m -s /bin/bash asf 2>/dev/null || log "Пользователь 'asf' уже существует"

arch=$(dpkg --print-architecture)
log "Определена архитектура: $arch"

case $arch in
  armhf)
    asf_url="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm.zip"
    ;;
  arm64)
    asf_url="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm64.zip"
    ;;
  amd64)
    asf_url="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-x64.zip"
    ;;
  *)
    warn "Архитектура $arch не поддерживается ASF. Установка пропущена"
    asf_skip=true
    ;;
esac

if [ -z "$asf_skip" ]; then
  log "Скачивание ArchiSteamFarm"
  sudo -u asf bash -c "
    cd ~ &&
    curl -LO $asf_url &&
    unzip ASF-linux-*.zip -d ASF &&
    rm ASF-linux-*.zip
  " || error "Ошибка при установке ASF"

  log "Настройка systemd-сервиса для ASF"
  cat <<EOF > /etc/systemd/system/asf.service
[Unit]
Description=ArchiSteamFarm
After=network.target

[Service]
User=asf
WorkingDirectory=/home/asf/ASF
ExecStart=/usr/bin/mono ArchiSteamFarm.exe
Environment=DOTNET_GCHeapHardLimit=1C0000000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable asf
  systemctl start asf
  log "Статус сервиса ASF:"
  systemctl status asf --no-pager
else
  warn "Установка ASF пропущена из-за неподдерживаемой архитектуры"
fi

# --- Шаг 4: Установка FunPayCardinal ---
info "Установка FunPayCardinal (FPC)"
log "Создание пользователя '$fpc_user'"
useradd -m -s /bin/bash "$fpc_user" || log "Пользователь '$fpc_user' уже существует"

log "Получение списка версий с GitHub"
gh_repo="sidor0912/FunPayCardinal"
versions=($(curl -sS https://api.github.com/repos/$gh_repo/releases | grep tag_name | awk '{print $2}' | sed 's/"//g;s/,//g'))

echo -e "${YELLOW}Доступные версии:${RESET}"
for i in "${!versions[@]}"; do
  echo "  $i) ${versions[$i]}"
done
echo -n -e "${CYAN}Выберите номер версии (или 'latest'): ${RESET}"
read version_choice

if [[ "$version_choice" == "latest" || -z "$version_choice" ]]; then
  dl_url=$(curl -sS https://api.github.com/repos/$gh_repo/releases/latest | jq -r '.zipball_url')
else
  dl_url=$(curl -sS https://api.github.com/repos/$gh_repo/releases | jq -r ".[] | select(.tag_name == \"${versions[$version_choice]}\") | .zipball_url")
fi

log "Скачивание и распаковка FPC"
sudo -u "$fpc_user" bash -c "
  cd ~ &&
  mkdir -p fpc-install &&
  cd fpc-install &&
  curl -L $dl_url -o fpc.zip &&
  unzip fpc.zip &&
  mv */* ../ &&
  cd .. &&
  rm -rf fpc-install
" || error "Ошибка при установке FPC"

log "Настройка Python окружения"
sudo -u "$fpc_user" bash -c "
  cd ~ &&
  python3.12 -m venv pyvenv &&
  ./pyvenv/bin/pip install -U pip &&
  ./pyvenv/bin/pip install -r FunPayCardinal/requirements.txt
" || error "Ошибка при настройке Python"

# --- Завершение ---
info "Финальная настройка"
log "Запуск FPC в screen-сессии"
sudo -u "$fpc_user" screen -dmS fpc_session bash -c "
  cd ~/FunPayCardinal &&
  ../pyvenv/bin/python main.py
"

echo -e "${CYAN}================================================================================${RESET}"
echo -e "${GREEN}Установка успешно завершена!${RESET}"
echo -e "Доступные компоненты:"
[ -z "$asf_skip" ] && \
echo -e "  - ASF: ${YELLOW}http://$(curl -s ifconfig.me):1242${RESET} (логин: пароль из конфига)"
echo -e "  - FPC: ${YELLOW}screen -r -U fpc_session${RESET} (под пользователем $fpc_user)"
echo -e "Пути конфигурации:"
[ -z "$asf_skip" ] && \
echo -e "  - ASF config: ${YELLOW}/home/asf/ASF/config${RESET}"
echo -e "  - FPC config: ${YELLOW}/home/$fpc_user/FunPayCardinal${RESET}"
echo -e "${CYAN}================================================================================${RESET}"
