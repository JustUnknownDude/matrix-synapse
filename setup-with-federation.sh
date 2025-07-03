#!/bin/bash
handle_error() {
    echo "An error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

read -p "Enter your domain: " DOMAIN
read -p "Enter your email for Certbot: " EMAIL
read -p "Enter login for admin user: " ADMINUSER
read -p "Enter password for admin user: " ADMINPASS
#INSTALL MATRIX
echo "INSTALL MATRIX.."
apt-get update && apt -y install nginx
apt install -y python3-certbot-nginx
apt install -y lsb-release wget apt-transport-https
wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/matrix-org.list
apt update
AUTHSECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
PASSWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
echo $AUTHSECRET > /root/key.txt
apt install -y matrix-synapse-py3
mv /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/homeserver-orig.yaml

cat << EOF > /etc/matrix-synapse/homeserver.yaml
pid_file: "/var/run/matrix-synapse.pid"
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client]
        compress: false
- port: 8448
    tls: true
    type: http
    x_forwarded: false
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [federation]
        compress: false
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client]
        compress: true
database:
  name: psycopg2
  txn_limit: 10000
  args:
    user: matrix
    password: $PASSWD
    database: matrix
    host: localhost
    port: 5432
    cp_min: 5
    cp_max: 10
log_config: "/etc/matrix-synapse/log.yaml"
media_store_path: /var/lib/matrix-synapse/media
signing_key_path: "/etc/matrix-synapse/homeserver.signing.key"
tls_certificate_path: "/etc/letsencrypt/live/x.$DOMAIN/fullchain.pem"
tls_private_key_path: "/etc/letsencrypt/live/x.$DOMAIN/privkey.pem"
trusted_key_servers:
  - server_name: "x.$DOMAIN"
suppress_key_server_warning: true
max_upload_size: 100M
enable_registration: false
matrix_synapse_federation_enabled: true
matrix_synapse_federation_port_enabled: true
registration_shared_secret: "$AUTHSECRET"
search_all_users: true
prefer_local_users: true
turn_uris: ["turn:x.$DOMAIN?transport=udp","turn:x.$DOMAIN?transport=tcp"]
turn_shared_secret: "$AUTHSECRET"
turn_user_lifetime: 86400000
admin_users:
  - "@$ADMINUSER:x.$DOMAIN"

EOF

systemctl enable matrix-synapse

cat << EOF > /etc/nginx/sites-enabled/x.conf
server {
server_name x.$DOMAIN;
location / {
	proxy_pass http://localhost:8008;
	proxy_set_header X-Forwarded-For \$remote_addr;
			}
			
listen 80;
}
EOF
nginx -s reload
certbot -n --nginx -d x.$DOMAIN --agree-tos -m  $EMAIL  --redirect
cat << EOF >> /etc/nginx/sites-enabled/x.conf
server {
    listen 8448 ssl;
    server_name x.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/x.$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/x.$DOMAIN/privkey.pem;

    location /_matrix {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
    }
}
EOF
nginx -s reload
systemctl start matrix-synapse
echo "Done."
#INSTALL POSTGRESQL
echo "INSTALL POSTGRESQL.."
apt install -y postgresql

su postgres -c "createuser matrix"
su postgres -c "createdb --encoding=UTF8 --locale=C --template=template0 --owner=matrix matrix"
su postgres -c "psql -c \"ALTER USER matrix WITH PASSWORD '$PASSWD';\""
echo "Done."

#INSTALL  COTURN
echo "INSTALL COTURN.."

apt install -y python3-psycopg2
ufw allow 8448
ufw allow https
apt install -y coturn
systemctl restart matrix-synapse.service

register_new_matrix_user -u $ADMINUSER -p $ADMINPASS -a -c /etc/matrix-synapse/homeserver.yaml http://localhost:8008

#echo 'deb https://download.jitsi.org stable/' >> /etc/apt/sources.list.d/jitsi-stable.list
#wget -qO -  https://download.jitsi.org/jitsi-key.gpg.key | sudo apt-key add -
#apt-get update
#apt-get -y install jitsi-meet
mv /etc/turnserver.conf /etc/turnserver.conf.orig

cat << EOF > /etc/turnserver.conf
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$AUTHSECRET
#Мы еге генерировали ранее во время настройки Matrix Synapse
realm=x.$DOMAIN
# consider whether you want to limit the quota of relayed streams per user (or total) to avoid risk of DoS.
user-quota=100 # 4 streams per video call, so 100 streams = 25 simultaneous relayed calls per user.
total-quota=1200
no-tcp-relay
# VoIP traffic is all UDP. There is no reason to let users connect to arbitrary TCP endpoints via the relay.
syslog
no-multicast-peers
EOF

echo "TURNSERVER_ENABLED=1" >> /etc/default/coturn

systemctl enable coturn --now
echo "Done."
#INSTALL ELENENT WEB
echo "INSTALL ELENENT WEB"
apt install -y docker.io docker-compose
mkdir /opt/element-web
cd /opt/element-web
cat << EOF > /opt/element-web/config.json
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://x.$DOMAIN",
            "server_name": "x.$DOMAIN"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "disable_custom_urls": true,
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": true,
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "uisi_autorageshake_app": "element-auto-uisi",
    "default_country_code": "GB",
    "show_labs_settings": false,
    "features": {},
    "default_federate": false,
    "default_theme": "light",
    "room_directory": {
        "servers": ["$DOMAIN"]
    },
    "enable_presence_by_hs_url": {
        "https://x.$DOMAIN": true
    },
    "terms_and_conditions_links": [
        {
            "url": "https://element.io/privacy",
            "text": "Privacy Policy"
        },
        {
            "url": "https://element.io/cookie-policy",
            "text": "Cookie Policy"
        }
    ],
    "privacy_policy_url": "https://element.io/cookie-policy"
}
EOF
docker run -d --name element-web --restart always -p 127.0.0.1:8090:80 -v /opt/element-web/config.json:/app/config.json vectorim/element-web:latest
echo "Done."
#INSTALL ELENENT ADMIN PANEL
echo "ELENENT ADMIN PANEL"
cd /opt
git clone https://github.com/Awesome-Technologies/synapse-admin.git
cat << EOF > /opt/synapse-admin/docker-compose.yml
version: "3"

services:
  synapse-admin:
    container_name: synapse-admin
    hostname: synapse-admin
    image: awesometechnologies/synapse-admin:latest
    build:
     context: .
     args:
      - REACT_APP_SERVER="https://x.$DOMAIN"
    ports:
      - "127.0.0.1:8080:80"
    restart: unless-stopped
EOF

cd /opt/synapse-admin/
docker-compose up -d > /dev/null 2>&1
cat << EOF > /etc/nginx/sites-enabled/xadm.conf
server {
   listen 80;
   listen [::]:80;
   server_name xadm.$DOMAIN;

    location / {
        #allow your_IP_address; #Allowed IP
        #deny all;
        proxy_pass http://localhost:8088/;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }

}
EOF
cat << EOF > /etc/nginx/sites-enabled/xweb.conf
server {
        listen 80;
        listen [::]:80;
    server_name xweb.$DOMAIN;

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "frame-ancestors 'self'";

    location / {
        proxy_pass http://localhost:8090;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }

}
EOF
nginx -s reload

certbot -n --nginx -d xadm.$DOMAIN --agree-tos -m  $EMAIL  --redirect
certbot -n --nginx -d xweb.$DOMAIN --agree-tos -m  $EMAIL  --redirect

systemctl restart matrix-synapse.service
echo "Done.\n"
echo "-------------------------\n"
echo "Admin panel: xadm.$DOMAIN\n"
echo "Element web: xweb.$DOMAIN\n"
echo "-------------------------\n"
echo "Element server address: x.$DOMAIN\n"
echo "-------------------------\n"
echo "Admin login: @$ADMINUSER\n"
echo "Admin password: @$ADMINPASS\n"
echo "Federation must work, check it please\n"
