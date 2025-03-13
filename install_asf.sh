#!/bin/bash
# Объединённый скрипт установки ASF и FPC с расширенной отладкой
# Автор: exfador (на основе работ sidor0912 и JustArchiNET)

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
echo "Объединённый установщик ASF и FPC с расширенной отладкой"
echo "Создан @exfador на основе:"
echo "- ArchiSteamFarm от JustArchiNET"
echo "- FunPayCardinal от sidor0912"
echo -e "${RESET}"

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
info "Начинаем обновление системы"
log "Обновление списка пакетов"
sudo apt update -y || error "Ошибка при обновлении списка пакетов"
log "Обновление установленных пакетов"
sudo apt upgrade -y || error "Ошибка при обновлении пакетов"

info "Установка необходимых зависимостей"
log "Устанавливаем: curl unzip screen jq mono-runtime libicu72 python3.12"
sudo apt install -y curl unzip screen jq mono-runtime libicu72 python3.12 || error "Ошибка при установке зависимостей"

# --- Шаг 3: Установка ArchiSteamFarm ---
info "Начинаем установку ArchiSteamFarm"
log "Создание пользователя 'asf'"
sudo useradd -m asf 2>/dev/null || log "Пользователь 'asf' уже существует"

arch=$(dpkg --print-architecture)
log "Определена архитектура: $arch"

case $arch in
  arm|armhf)
    info "Выбрана версия для ARM 32-bit"
    asf_url="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm.zip"
    ;;
  arm64|aarch64)
    info "Выбрана версия для ARM 64-bit"
    asf_url="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm64.zip"
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

  log "Создание systemd-сервиса для ASF"
  echo "[Unit]
Description=ArchiSteamFarm
After=network.target

[Service]
User=asf
WorkingDirectory=/home/asf/ASF
ExecStart=/usr/bin/mono ArchiSteamFarm.exe
Environment=DOTNET_GCHeapHardLimit=1C0000000
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/asf.service >/dev/null

  log "Активация сервиса ASF"
  sudo systemctl enable asf
  sudo systemctl start asf
  log "Статус сервиса ASF:"
  sudo systemctl status asf --no-pager
else
  warn "Установка ASF пропущена из-за неподдерживаемой архитектуры"
fi

# --- Шаг 4: Установка FunPayCardinal ---
info "Начинаем установку FunPayCardinal"
log "Создание пользователя '$fpc_user'"
sudo useradd -m "$fpc_user" 2>/dev/null || log "Пользователь '$fpc_user' уже существует"

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
  info "Выбрана последняя версия"
  dl_url=$(curl -sS https://api.github.com/repos/$gh_repo/releases/latest | jq -r '.zipball_url')
else
  info "Выбрана версия ${versions[$version_choice]}"
  dl_url=$(curl -sS https://api.github.com/repos/$gh_repo/releases | jq -r ".[] | select(.tag_name == \"${versions[$version_choice]}\") | .zipball_url")
fi

log "Создание директорий для установки"
sudo -u "$fpc_user" bash -c "
  cd ~ &&
  mkdir -p fpc-install &&
  cd fpc-install
" || error "Ошибка при создании директорий"

log "Скачивание FunPayCardinal"
sudo -u "$fpc_user" curl -L $dl_url -o fpc.zip || error "Ошибка при скачивании архива"

log "Распаковка архива"
sudo -u "$fpc_user" unzip fpc.zip -d . || error "Ошибка при распаковке"
sudo -u "$fpc_user" mv */* .. || error "Ошибка при перемещении файлов"
sudo -u "$fpc_user" cd .. && rm -rf fpc-install || error "Ошибка при очистке"

log "Создание виртуального окружения Python"
sudo -u "$fpc_user" python3.12 -m venv pyvenv || error "Ошибка при создании venv"
sudo -u "$fpc_user" ./pyvenv/bin/pip install -U pip || error "Ошибка при обновлении pip"

log "Установка зависимостей"
sudo -u "$fpc_user" ./pyvenv/bin/pip install -r FunPayCardinal/requirements.txt || error "Ошибка при установке зависимостей"

# --- Завершение ---
info "Почти готово! Выполняем финальные настройки"
log "Запуск FPC через screen"
sudo -u "$fpc_user" screen -dmS fpc_session bash -c "
  cd ~/FunPayCardinal &&
  ../pyvenv/bin/python main.py
"

log "Проверка запущенных процессов"
ps aux | grep -E 'ArchiSteamFarm|FunPayCardinal' || warn "Процессы не обнаружены"

echo -e "${CYAN}################################################################################${RESET}"
echo -e "${CYAN}Установка завершена!${RESET}"
echo -e "${GREEN}Детали:${RESET}"
echo -e "  - ASF: ${YELLOW}http://$(curl -s ifconfig.me):1242${RESET} (если установлен)"
echo -e "  - FPC: ${YELLOW}screen -r fpc_session${RESET} (пользователь: $fpc_user)"
echo -e "  - Конфиги ASF: ${YELLOW}/home/asf/ASF/config${RESET}"
echo -e "  - Конфиги FPC: ${YELLOW}/home/$fpc_user/FunPayCardinal${RESET}"
echo -e "${CYAN}################################################################################${RESET}"

log "Важно: Проверьте открытые порты и настройте брандмауэр при необходимости"
