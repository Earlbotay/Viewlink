#!/bin/bash
# Pterodactyl Panel & Wings 100% Auto Installer + All Bot Hosting Eggs (NodeJS, Python, Discord, Telegram, etc)
# By Earlbotay

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

echo "Updating system..."
apt update -y && apt upgrade -y

echo "Installing dependencies..."
apt install -y curl wget unzip tar git redis-server nginx mysql-server \
  php php-fpm php-cli php-mysql php-zip php-gd php-mbstring php-xml php-curl \
  php-redis php-async redis jq nodejs python3 python3-pip

echo "Installing Node.js (latest)..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

MYSQL_ROOT_PASSWORD="pteropass"
echo "Configuring MySQL..."
mysql -u root <<-EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<-EOF
CREATE DATABASE panel;
CREATE USER 'ptero'@'localhost' IDENTIFIED BY 'panelpass';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Downloading Pterodactyl Panel..."
cd /var/www/
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz
cd /var/www/panel

composer install --no-dev --optimize-autoloader
npm install --production

chown -R www-data:www-data /var/www/panel
chmod -R 755 /var/www/panel

cp .env.example .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=panelpass/" .env

php artisan key:generate
php artisan migrate --seed --force

cat > /etc/nginx/sites-available/pterodactyl <<EOL
server {
    listen 80;
    server_name _;
    root /var/www/panel/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }
    location ~ /\.ht { deny all; }
}
EOL
ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
systemctl restart nginx

echo "Downloading Wings..."
mkdir -p /etc/pterodactyl
curl -Lo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x /usr/local/bin/wings

cat > /etc/pterodactyl/config.yml <<EOL
token: "changeme"
api:
  host: 0.0.0.0
  port: 8080
EOL

cat > /etc/systemd/system/wings.service <<EOL
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings.pid
ExecStart=/usr/local/bin/wings
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable --now wings

# Download ALL Bot Hosting Eggs (NodeJS, Python, Discord, Telegram, WhatsApp, etc)
mkdir -p /var/lib/pterodactyl-eggs
# Eggs source: https://github.com/parkervcp/eggs
curl -Lo /var/lib/pterodactyl-eggs/nodejs_bot.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/nodejs_bot.json
curl -Lo /var/lib/pterodactyl-eggs/python_bot.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/python_bot.json
curl -Lo /var/lib/pterodactyl-eggs/discordjs.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/discord/discordjs.json
curl -Lo /var/lib/pterodactyl-eggs/discordpy.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/discord/discordpy.json
curl -Lo /var/lib/pterodactyl-eggs/telegram_bot.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/telegram/telegram_bot.json
curl -Lo /var/lib/pterodactyl-eggs/whatsapp_baileys.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/whatsapp/baileys.json
curl -Lo /var/lib/pterodactyl-eggs/whatsapp_venom.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/whatsapp/venom.json
curl -Lo /var/lib/pterodactyl-eggs/simplejs.json https://raw.githubusercontent.com/parkervcp/eggs/master/bots/simplejs.json

echo "=== INSTALLATION COMPLETE ==="
echo "Panel: http://$(hostname -I | awk '{print $1}')"
echo "MySQL root password: $MYSQL_ROOT_PASSWORD"
echo "Panel DB: panel / User: ptero / Pass: panelpass"
echo "Wings daemon running."
echo "Eggs for JS, Python, Discord, Telegram, WhatsApp bot in /var/lib/pterodactyl-eggs"
