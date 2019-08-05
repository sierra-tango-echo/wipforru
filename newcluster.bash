#!/bin/bash

CLUSTERPACK=$1

if ! [ -f /${CLUSTERPACK} ]; then
  echo "Full path to clusterpack plz" >&2
  exit 1
fi

source $CLUSTERPACK

if [ -z "$CLUSTERNAME" ]; then
  echo "Duff clusterpack" >&2
  exit 1
fi

#Probably want to validate the clusterpack makes sense here as well


#create the cluster
echo "ifconfig-push $CLIENTIP $SERVERIP" > /etc/openvpn/ccd-cluster/$CLUSTERNAME
useradd -M -N -s /sbin/nologin $CLUSTERNAME
echo "${CLUSTERNAME}:${CLUSTERPASSWORD}" | chpasswd
echo "${CLUSTERNAME}" >> /etc/openvpn/cluster.users
#generate an install script
mkdir -p /etc/openvpn/clientscripts/
cat << EOD > /etc/openvpn/clientscripts/$CLUSTERNAME.sh

yum install epel-release -y
yum install openvpn -y

cat << EOF > /etc/openvpn/flighthub.conf
client
dev tun0
proto tcp
remote `dig @resolver1.opendns.com ANY myip.opendns.com +short` 1195
resolv-retry infinite
nobind
persist-key
persist-tun
<ca>
`cat /etc/openvpn/easyrsa/pki/ca.crt`
</ca>
auth-user-pass auth.flighthub
ns-cert-type server
comp-lzo
verb 3
EOF

systemctl start openvpn@flighthub
EOD

#Check i'm open
(curl -sd port="1195" https://canyouseeme.org |grep -qo 'Success') || echo "WARNING! - Cannot get at 1195"
