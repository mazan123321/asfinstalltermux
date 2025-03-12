#!/bin/bash

# Обновление пакетов Termux
echo "Обновление пакетов Termux..."
pkg update && pkg upgrade -y

# Установка необходимых зависимостей
echo "Установка необходимых зависимостей..."
pkg install proot-distro wget curl git -y

# Установка Ubuntu через proot-distro
echo "Установка Ubuntu через proot-distro..."
proot-distro install ubuntu

# Запуск Ubuntu и выполнение команд внутри chroot
echo "Настройка Ubuntu..."
proot-distro login ubuntu --shared-tmp -- bash <<EOF
# Обновление пакетов Ubuntu
apt update && apt upgrade -y

# Установка зависимостей
apt install wget curl git unzip mono-complete -y

# Создание пользователя для ASF
adduser --disabled-password --gecos "" asfuser
su - asfuser -c "mkdir ~/asf"

# Скачивание и распаковка ASF
su - asfuser -c "wget https://github.com/JustArchiNET/ArchiSteamFarm/releases/latest/download/ASF-linux-x64.zip -O ~/asf/asf.zip"
su - asfuser -c "unzip ~/asf/asf.zip -d ~/asf"

# Создание базового конфигурационного файла
su - asfuser -c "mkdir ~/asf/config"
cat <<CONFIG > /home/asfuser/asf/config/asf.json
{
  "IPC": true,
  "Headless": true
}
CONFIG

# Создание конфигурации бота
cat <<BOTCONFIG > /home/asfuser/asf/config/bot.json
{
  "SteamLogin": "your_username",
  "SteamPassword": "your_password",
  "Enabled": true
}
BOTCONFIG

# Создание скрипта автозапуска
cat <<AUTOSTART > /usr/local/bin/start_asf.sh
#!/bin/bash
su - asfuser -c "cd ~/asf && mono ArchiSteamFarm.exe"
AUTOSTART

chmod +x /usr/local/bin/start_asf.sh

# Выход из chroot
EOF

# Настройка ярлыка для Termux Widget
echo "Создание ярлыка для Termux Widget..."
cat <<SHORTCUT > ~/start_asf_shortcut.sh
#!/bin/bash
proot-distro login ubuntu --shared-tmp -- bash -c "/usr/local/bin/start_asf.sh"
SHORTCUT

chmod +x ~/start_asf_shortcut.sh

# Инструкция для пользователя
echo "Установка завершена!"
echo "Чтобы запустить ASF, выполните команду: ~/start_asf_shortcut.sh"
echo "Вы также можете добавить этот ярлык в Termux Widget для быстрого доступа."