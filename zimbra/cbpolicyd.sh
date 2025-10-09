#!/bin/bash

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

echo "Starting CBPolicyD installation and configuration for Zimbra..."

# Enable cbpolicyd service for the current mail server
su - zimbra -c "zmprov ms \$(zmhostname) +zimbraServiceInstalled cbpolicyd +zimbraServiceEnabled cbpolicyd"

# Backup existing cbpolicyd config
CBPOLICYDCONF="$(mktemp /tmp/cbpolicyd.conf.in.XXXXXXXX)"
echo "Backing up /opt/zimbra/conf/cbpolicyd.conf.in to ${CBPOLICYDCONF}"
cp -a /opt/zimbra/conf/cbpolicyd.conf.in "${CBPOLICYDCONF}"

# Enable CBPolicyD features: access control and quotas
su - zimbra -c "zmprov ms \$(zmhostname) zimbraCBPolicydAccessControlEnabled TRUE"
su - zimbra -c "zmprov ms \$(zmhostname) zimbraCBPolicydQuotasEnabled TRUE"

# Optional: Add MTA restriction to enable policy service (uncomment if needed)
# su - zimbra -c "zmprov mcf +zimbraMtaRestriction 'check_policy_service inet:127.0.0.1:10031'"

# Optional: Set logging level (1-4)
# su - zimbra -c "zmprov ms \$(zmhostname) zimbraCBPolicydLogLevel 4"

# Configure cbpolicyd.conf.in for SQLite
CONFIG_FILE="/opt/zimbra/conf/cbpolicyd.conf.in"

echo "Updating Username in cbpolicyd.conf.in"
sed -i "s/^.*Username=.*$/Username=root/" "$CONFIG_FILE"

echo "Updating Password in cbpolicyd.conf.in"
sed -i "s/^.*Password=.*$/Password=/" "$CONFIG_FILE"

echo "Setting DSN to use SQLite"
sed -i "s|^DSN=.*$|DSN=DBI:sqlite:dbname=/opt/zimbra/data/cbpolicyd/db/cbpolicyd.sqlitedb|" "$CONFIG_FILE"

# Restart Zimbra MTA and cbpolicyd service
echo "Restarting Zimbra MTA and CBPolicyD..."
su - zimbra -c "zmmtactl restart"
su - zimbra -c "zmcbpolicydctl restart"

# Set up web UI authentication
WEBUI_DIR="/opt/zimbra/common/share/webui"
HTPASSWD_FILE="$WEBUI_DIR/.htpasswd"

echo "Creating htpasswd for web UI access..."

# Prompt for username
read -rp "Enter username for web UI login: " WEBUI_USER

# Prompt for password securely
read -rsp "Enter password for $WEBUI_USER: " WEBUI_PASS
echo
read -rsp "Confirm password: " WEBUI_PASS_CONFIRM
echo

# Check if passwords match
if [[ "$WEBUI_PASS" != "$WEBUI_PASS_CONFIRM" ]]; then
  echo "Error: Passwords do not match. Aborting."
  exit 1
fi

# Create or overwrite the htpasswd file with user credentials
/opt/zimbra/common/bin/htpasswd -cb "$HTPASSWD_FILE" "$WEBUI_USER" "$WEBUI_PASS"
echo "Web UI credentials created for user: $WEBUI_USER"

# Create .htaccess file in the web UI directory
cat <<EOF > "$WEBUI_DIR/.htaccess"
AuthUserFile $HTPASSWD_FILE
AuthGroupFile /dev/null
AuthName "User and Password"
AuthType Basic
require valid-user
EOF

# Update Apache httpd.conf to serve CBPolicyD web UI
HTTPD_CONF="/opt/zimbra/conf/httpd.conf"
if ! grep -q "Alias /webui" "$HTTPD_CONF"; then
  echo "Adding CBPolicyD web UI configuration to $HTTPD_CONF"
  cat <<EOF >> "$HTTPD_CONF"

# CBPolicyD WebUI Alias
Alias /webui /opt/zimbra/common/share/webui/
<Directory /opt/zimbra/common/share/webui/>
    AllowOverride AuthConfig
    Order Deny,Allow
    Allow from all
</Directory>
EOF
else
  echo "Web UI Alias already configured in $HTTPD_CONF"
fi

# Restart Apache to apply changes
echo "Restarting Apache..."
su - zimbra -c "zmapachectl restart"

# Final message
echo
echo "✅ CBPolicyD setup completed!"
echo "You can access the web UI at: http://$(hostname -f):7780/webui/index.php"
echo
echo "🔍 Logs: tail -f /opt/zimbra/log/cbpolicyd.log"