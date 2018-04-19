#!/bin/bash
source vm1.config
export $(cut -d= -f1 vm1.config)

if [ "$EXT_IP" = "DHCP" ]; then
    echo "Setting external interface by DHCP"
    ip link set up $EXTERNAL_IF
    dhclient $EXTERNAL_IF
else
    echo "Setting static external IP"
    ip addr add $EXT_IP dev $EXTERNAL_IF
    echo "Raising external IP"
    ip link set up $EXTERNAL_IF
    echo "Adding default route"
    ip route add default via $EXT_GW
    echo "Adding nameserver"
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

echo "Raising internal IP"
ip link set up $INTERNAL_IF
echo "Inserting VLAN module"
modprobe 8021q
echo "Adding VLAN"
vconfig add $INTERNAL_IF $VLAN
echo "Adding VLAN IP"
ip addr add $VLAN_IP dev $INTERNAL_IF.$VLAN
echo "Raising VLAN"
ip link set up $INTERNAL_IF.$VLAN

echo "Enable IP forwarding"
sysctl net.ipv4.ip_forward=1
echo "Setting NAT"
iptables -t nat -A POSTROUTING -o $EXTERNAL_IF -j MASQUERADE

export EXT_IP=$(ip -o -4 -a addr show $EXTERNAL_IF|tr -s ' '| cut -d ' ' -f 4|head -n 1|cut -d '/' -f 1)
envsubst '$EXT_IP' < subjalt_template.cnf > subjalt.cnf

echo "Making dir for certs"
mkdir -p /etc/ssl/certs
if [ ! -e /etc/ssl/certs/root-ca.key ]
then
echo "Root cert is absent, generating. Dont forget to import it for curl --cacert"
openssl genrsa -out /etc/ssl/certs/root-ca.key 4096
else
echo "Root cert present"
fi

openssl req -x509 -new -nodes -key /etc/ssl/certs/root-ca.key -sha256 -days 365\
       -out /etc/ssl/certs/root-ca.crt\
       -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Mirantis/OU=dev_ops/CN=vm1/"\
       -extensions v3_req\
       -config <(cat /etc/ssl/openssl.cnf; cat subjalt.cnf)

echo "Generating web.key"
openssl genrsa -out /etc/ssl/certs/web.key 2048
echo "Generating web.csr"
openssl req -new\
       -out /etc/ssl/certs/web.csr\
       -key /etc/ssl/certs/web.key\
       -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Mirantis/OU=dev_ops/CN=vm1/"
openssl x509 -req\
       -in /etc/ssl/certs/web.csr\
       -CA /etc/ssl/certs/root-ca.crt\
       -CAkey /etc/ssl/certs/root-ca.key\
       -CAcreateserial\
       -out /etc/ssl/certs/web.crt
cat /etc/ssl/certs/root-ca.crt /etc/ssl/certs/web.crt> \
    /etc/ssl/certs/web-ca-chain.pem

IS_NGINX_INSTALLED=$(dpkg -l nginx | grep ii |wc -l)
if [ $IS_NGINX_INSTALLED = 0 ]
then
    echo "NGINX is absent, installing"
    echo "Updating apt"
    apt update
    echo "Installing NGINX"
    apt install nginx -y -q
    envsubst '$APACHE_VLAN_IP $NGINX_PORT' < default > /etc/nginx/sites-enabled/default
    echo "Restarting NGINX"
        systemctl restart nginx
else
     echo "NGINX installed earlier"
     systemctl restart nginx
fi
