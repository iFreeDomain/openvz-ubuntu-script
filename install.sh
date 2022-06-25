
#!/bin/bash

#Variables
IP=$(hostname -I | awk '{print $2}')
PasswordGenerator=$(</dev/urandom tr -dc '[:alnum:]' | head -c15; echo "")
SslKeyPath='/etc/nginx/ssl/priv.key'
SslCertPath='/etc/nginx/ssl/ssl.crt'
export DEBIAN_FRONTEND=noninteractive

#Set proper mirrors
mv /etc/apt/sources.list /etc/apt/sources.list_backup
tee /etc/apt/sources.list <<EOF
deb https://mirrors.neterra.net/ubuntu/ focal main restricted universe
deb https://mirrors.neterra.net/ubuntu/ focal-updates main restricted universe
deb https://mirrors.neterra.net/ubuntu/ focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner
EOF

#Install Software
apt-get -yq --allow-releaseinfo-change update
printf '\n' | apt-get install -y apt-transport-https ca-certificates curl software-properties-common apache2-utils

#Install and configure nginx + SSL + Proxy pass
apt-get install -y nginx
mkdir /etc/nginx/ssl
openssl genrsa -out /etc/nginx/ssl/priv.key 2048
printf '\n\n\n\n\n\n\n\n' | openssl req -key /etc/nginx/ssl/priv.key -new -x509 -days 3650 -out /etc/nginx/ssl/ssl.crt
htpasswd -c -B -b /etc/nginx/.htpasswd dedicatedvpn $PasswordGenerator

tee -a /etc/nginx/sites-available/ui.conf <<EOF
server {

    listen              7654 ssl;
    listen              [::]:7654 ssl;
    error_page 497 https://$IP:7654;
    server_name         $IP;
    root                /var/www/html/;
    error_log   /dev/null   crit;
    access_log  /dev/null;

    # SSL
    ssl_certificate     $SslCertPath;
    ssl_certificate_key $SslKeyPath;

    # reverse proxy
    location / {
        auth_basic "Restricted"; auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://127.0.0.1:8080;
    }

}
EOF

ln -s /etc/nginx/sites-available/ui.conf /etc/nginx/sites-enabled/ui.conf
rm -rf /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
systemctl restart nginx

#Install docker and docker compose
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
apt-get -yq --allow-releaseinfo-change update
printf '\n' | apt-get -yq install docker-ce
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

#Enable docker
systemctl start docker
systemctl enable docker

#Setup OVPN and the UI
mkdir /home/ovpn-admin 
cd /home/ovpn-admin
wget http://files.vps.bg/vpn/openvpn/ovpn-admin-1.7.5.tar 
tar xvf ovpn-*
sed -i "s/127.0.0.2/$IP/g" docker-compose.yaml
./start.sh

docker update --restart unless-stopped $(docker ps -q)

#Configure SSH.
sed -i "s/#Port 22/Port 22000/g" /etc/ssh/sshd_config
systemctl restart sshd

#Create first user
data()
{
cat <<EOF
username=dedicatedvpn
EOF
}

until curl -s -f -o /dev/null -X POST -d "$(data)" "http://127.0.0.1:8080/api/user/create"
do
  sleep 5
done

#VPSBG Credentials
until curl -s -f -o /dev/null -X POST -d "$(data)" "http://127.0.0.1:8080/api/user/config/show"
do
  sleep 2
done

ClientConfig=$(curl -X POST -d "$(data)" "http://127.0.0.1:8080/api/user/config/show")
curl -X POST --data-urlencode "token=XXXXXX" --data-urlencode "ovpn=$ClientConfig" --data-urlencode "web=$PasswordGenerator" "https://secure.vpsbg.eu/XXXXXXX"

#Remove Bloatware 
apt-get purge exim* apache2* pwgen tcpdump telnet -y

#Upgrade the server system
printf '\n' | apt-get -yq upgrade
apt-get clean
