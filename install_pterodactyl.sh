#!/bin/bash
# Auto Installer Pterodactyl Panel, Wings & Egg (Ubuntu 20.04/22.04)
# By Earlbotay

set -e

echo "=== Pterodactyl Auto Installer ==="
echo "For Ubuntu 20.04/22.04 only."
echo "Root privileges required."

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Update & Install dependencies
apt update && apt upgrade -y
apt install -y curl wget unzip tar git redis-server nginx mysql-server \
  php php-fpm php-cli php-mysql php-zip php-gd php-mbstring php-xml php-curl \
  php-redis php-async redis jq

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Setup MySQL
MYSQL_ROOT_PASSWORD="pteropass"
echo "Setting MySQL root password..."
mysql -u root <<-EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Create Panel Database
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<-EOF
CREATE DATABASE panel;
CREATE USER 'ptero'@'localhost' IDENTIFIED BY 'panelpass';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download Pterodactyl Panel
cd /var/www/
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz
cd /var/www/panel

# Install Panel dependencies
composer install --no-dev --optimize-autoloader
npm install --production

# Set permissions
chown -R www-data:www-data /var/www/panel
chmod -R 755 /var/www/panel

# Setup .env (auto fill)
cp .env.example .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=panelpass/" .env

php artisan key:generate
php artisan migrate --seed --force

# Setup Nginx
cat > /etc/nginx/sites-available/pterodactyl <<EOL
server {
    listen 80;
    server_name _;
    root /var/www/panel/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
    }

    location ~ \.ht {
        deny all;
    }
}
EOL
ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
systemctl restart nginx

# Download Wings
mkdir -p /etc/pterodactyl
curl -Lo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x /usr/local/bin/wings

# Create Wings config (default)
cat > /etc/pterodactyl/config.yml <<EOL
# Minimal wings config
token: "changeme"
api:
  host: 0.0.0.0
  port: 8080
EOL

# Create systemd service for Wings
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

# Download example Egg (Minecraft Paper)
mkdir -p /var/lib/pterodactyl-eggs
curl -Lo /var/lib/pterodactyl-eggs/minecraft-paper.json https://raw.githubusercontent.com/parkervcp/eggs/master/game_eggs/minecraft/paper.json

echo "=== INSTALLATION COMPLETE ==="
echo "Panel: http://"+$(hostname -I | awk '{print $1}')

echo "MySQL root password: $MYSQL_ROOT_PASSWORD"
echo "Panel DB: panel / User: ptero / Pass: panelpass"
echo "Wings installed and running."
echo "Eggs downloaded ke /var/lib/pterodactyl-eggs"