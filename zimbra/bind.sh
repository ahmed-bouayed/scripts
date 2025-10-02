#!/bin/bash
set -o nounset
echo ""
echo -e "Internet connectivity is required for packages installation..."
echo ""
echo -e "Press key enter to continue"
read presskey

echo -e "[INFO] : Installing required dependencies"
sleep 3

## Update system
sudo yum update -y
sudo yum -y install bind bind-utils net-tools sysstat

# Configure Bind DNS Server
## Input required variables
echo ""
read -p "Input Zimbra Base Domain. E.g example.com : " ZIMBRA_DOMAIN
read -p "Input Zimbra Mail Server hostname (first part of FQDN). E.g mail : " ZIMBRA_HOSTNAME
read -p "Input Zimbra Server IP Address : " ZIMBRA_SERVERIP
read -p "Input Zimbra Server Gateway : " ZIMBRA_GATEWAY

echo ""
echo -e "[INFO] : Configuring DNS Server"
sleep 3
### Backup configs
BIND_CONFIG=$(ls /etc/ | grep named.conf.back);
if [ "$BIND_CONFIG" != "named.conf.back" ]; then
    sudo cp /etc/named.conf /etc/named.conf.back
fi
# Update DNS listen address
# If remote update address accordingly
sed -i 's/listen-on port 53 { 127\.0\.0\.1; };/listen-on port 53 { any; };/g' /etc/named.conf

### Configure DNS Zone
sudo tee -a /etc/named.conf<<EOF
zone "$ZIMBRA_DOMAIN" IN {
type master;
file "db.$ZIMBRA_DOMAIN";
};
EOF

sudo sed -i '/options\s*{/{a\
    forwarders {\
        8.8.8.8;\
        1.1.1.1;\
    };\
' /etc/named.conf

# Create Zone database file
sudo touch /var/named/db.$ZIMBRA_DOMAIN
sudo chgrp named /var/named/db.$ZIMBRA_DOMAIN

sudo tee /var/named/db.$ZIMBRA_DOMAIN<<EOF
\$TTL 1D
@       IN SOA  ns1.$ZIMBRA_DOMAIN. root.$ZIMBRA_DOMAIN. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
@		IN	NS	ns1.$ZIMBRA_DOMAIN.
@		IN	MX	0 $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN.
ns1	IN	A	$ZIMBRA_SERVERIP
mail	IN	A	$ZIMBRA_SERVERIP
EOF
  
sudo tee /etc/resolv.conf<<EOF
search $ZIMBRA_DOMAIN
nameserver 127.0.0.1
EOF

# Restart Service & Check results configuring DNS Server
sudo systemctl enable named
sudo systemctl restart named

nmcli con mod eth0 ipv4.method manual ipv4.addresses $ZIMBRA_SERVERIP/24 ipv4.gateway $ZIMBRA_GATEWAY ipv4.dns "127.0.0.1"
# Test DNS setup
nslookup $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN
dig $ZIMBRA_DOMAIN mx
