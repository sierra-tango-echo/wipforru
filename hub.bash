#!/bin/bash

#Make sure we have decent firewall basics
yum -y install firewalld
systemctl enable firewalld 

yum install epel-release -y
yum install openvpn easy-rsa -y

if [ -d /etc/openvpn/easyrsa ]; then
  echo "no clean" >&2
  exit 1
fi

rsync -pav /usr/share/easy-rsa/3/ /etc/openvpn/easyrsa

cd /etc/openvpn/easyrsa

cat<< 'EOF' > /etc/openvpn/easyrsa/vars
if [ -z "$EASYRSA_CALLER" ]; then
    echo "You appear to be sourcing an Easy-RSA 'vars' file." >&2
    echo "This is no longer necessary and is disallowed. See the section called" >&2
    echo "'How to use this file' near the top comments for more details." >&2
    return 1
fi

set_var EASYRSA        "$PWD"
set_var EASYRSA_OPENSSL        "openssl"
set_var EASYRSA_PKI            "$EASYRSA/pki"
set_var EASYRSA_DN     "org"

set_var EASYRSA_REQ_COUNTRY    "UK"
set_var EASYRSA_REQ_PROVINCE   "Oxfordshire"
set_var EASYRSA_REQ_CITY       "Oxford"
set_var EASYRSA_REQ_ORG        "Alces Flight Ltd"
set_var EASYRSA_REQ_EMAIL      "ssl@alces-flight.com"
set_var EASYRSA_REQ_OU         "Infrastructure"
set_var EASYRSA_KEY_SIZE       2048

set_var EASYRSA_ALGO           rsa

set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    3650
set_var EASYRSA_CRL_DAYS       180

set_var EASYRSA_TEMP_FILE      "$EASYRSA_PKI/extensions.temp"

set_var EASYRSA_BATCH 		"true"
EOF

chmod 744 /etc/openvpn/easyrsa/vars

#Init things & build CA
./easyrsa init-pki  
./easyrsa build-ca nopass
./easyrsa gen-dh
./easyrsa gen-crl

#Generate hub keys
./easyrsa gen-req hub nopass
./easyrsa sign-req server hub

#Do config
cat << EOF > /etc/openvpn/cluster.conf
port 1195
proto tcp
dev tun1
ca /etc/openvpn/easyrsa/pki/ca.crt
cert /etc/openvpn/easyrsa/pki/issued/hub.crt
key /etc/openvpn/easyrsa/pki/private/hub.key
dh /etc/openvpn/easyrsa/pki/dh.pem
crl-verify /etc/openvpn/easyrsa/pki/crl.pem
server 10.178.0.0 255.255.255.0
ifconfig-pool-persist ipp-cluster
keepalive 10 60
comp-lzo
persist-key
persist-tun
status openvpn-status.log
log-append  /var/log/openvpn-clusters.log
verb 3
client-cert-not-required
username-as-common-name
plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so openvpn-cluster
client-config-dir ccd-cluster
ccd-exclusive
EOF

cat << EOF > /etc/pam.d/openvpn-cluster
#%PAM-1.0
auth [user_unknown=ignore success=ok ignore=ignore default=bad] pam_securetty.so
auth       substack     system-auth
auth       include      postlogin
auth       required     pam_listfile.so onerr=fail item=group sense=allow file=/etc/openvpn/clusters.users
account    required     pam_nologin.so
account    include      system-auth
password   include      system-auth
# pam_selinux.so close should be the first session rule
session    required     pam_selinux.so close
session    required     pam_loginuid.so
session    optional     pam_console.so
# pam_selinux.so open should only be followed by sessions to be executed in the user context
session    required     pam_selinux.so open
session    required     pam_namespace.so
session    optional     pam_keyinit.so force revoke
session    include      system-auth
session    include      postlogin
-session   optional     pam_ck_connector.so
EOF

#prep for our clients
mkdir /etc/openvpn/ccd-cluster
touch /etc/openvpn/ipp-cluster


