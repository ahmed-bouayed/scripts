#!/bin/bash
set -o nounset

# Install required packages
echo ""
echo -e "Internet connectivity is required for packages installation..."
echo ""
read -p "Press Enter key to continue:" presskey
#Update system and install key packages
sudo yum update -y
sudo yum -y install nano wget git tar perl perl-core net-tools tmux

echo -e "[INFO] : Configuring Firewall"
sudo systemctl stop firewalld
sudo systemctl disable firewalld

sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

## Input required variables
echo ""
read -p "Input Zimbra Base Domain. E.g example.com : " ZIMBRA_DOMAIN
read -p "Input Zimbra Mail Server hostname (first part of FQDN). E.g mail : " ZIMBRA_HOSTNAME
read -p "Please insert your IP Address : " ZIMBRA_SERVERIP
echo ""

echo "Update  hostname and /etc/hosts file.."
##Update system hostname."
sudo hostnamectl set-hostname $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN
## /etc/hosts update
sudo cp /etc/hosts /etc/hosts.backup
sudo tee /etc/hosts<<EOF
127.0.0.1       localhost
$ZIMBRA_SERVERIP   $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN       $ZIMBRA_HOSTNAME
EOF

##Validate
echo ""
hostnamectl
echo ""
echo "Zimbra server hostname is:"
hostname -f

read -p "Are you sure you want to reboot the system? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot canceled."
fi
