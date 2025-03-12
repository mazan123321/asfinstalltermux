#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}[*] Начинаем установку ASF...${NC}"

# Обновление Termux и установка proot-distro
echo -e "${YELLOW}[*] Обновление Termux и установка proot-distro...${NC}"
pkg update -y -o Dpkg::Options::="--force-confnew"
pkg install proot-distro -y
proot-distro install debian

# Установка зависимостей в Debian
echo -e "${YELLOW}[*] Установка зависимостей в Debian...${NC}"
proot-distro login debian -- bash -c 'apt update -y && apt upgrade -y && apt install libicu72 mono-runtime unzip curl -y'
proot-distro login debian -- bash -c 'useradd -m asf'

# Определение архитектуры и загрузка ASF
echo -e "${YELLOW}[*] Загрузка ASF для вашей архитектуры...${NC}"
arch=$(proot-distro login debian -- bash -c 'dpkg --print-architecture')
echo -e "Архитектура: ${CYAN}${arch}${NC}"

URL=""
case $arch in
    "arm"|"armhf") 
        URL="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm.zip" 
        ;;
    "arm64"|"aarch64") 
        URL="https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-arm64.zip" 
        ;;
    *)
        echo -e "${RED}[!] Неподдерживаемая архитектура!${NC}"
        exit 1
        ;;
esac

proot-distro login debian --user asf -- bash -c "curl -LO ${URL} && unzip *.zip -d ASF && rm *.zip"

# Настройка окружения
echo -e "${YELLOW}[*] Настройка окружения...${NC}"
ln -s /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/home/asf/ASF ~/ASF

# Создание ярлыков
echo -e "${YELLOW}[*] Создание ярлыков...${NC}"
mkdir -p ~/.shortcuts/icons
chmod 700 -R ~/.shortcuts
chmod -R a-x,u=rwX,go-rwx ~/.shortcuts/icons

curl -sL "https://raw.githubusercontent.com/JustArchiNET/ArchiSteamFarm/main/resources/ASF_184x184.png" > ~/.shortcuts/icons/ASF.png

# Скрипт запуска
cat > ~/.shortcuts/ASF <<EOL
#!/bin/bash
proot-distro login debian --user asf -- sh -c "if [ \"\\\$(pidof ArchiSteamFarm)\" ]; then echo \"ASF уже запущен\"; else export DOTNET_GCHeapHardLimit=1C0000000 && ~/ASF/ArchiSteamFarm; fi"
EOL

chmod +x ~/.shortcuts/ASF

echo -e "${GREEN}[✔] Установка завершена!${NC}"
echo -e "Для запуска ASF:"
echo -e "1. Добавьте виджет Termux:Widget на рабочий стол"
echo -e "2. Выберите скрипт ASF"
echo -e "3. Для доступа к веб-интерфейсу: ${CYAN}http://localhost:1242${NC}"
echo -e "Файлы конфигурации: ${CYAN}~/ASF/config${NC}"
