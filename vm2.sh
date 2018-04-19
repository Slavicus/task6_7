#!/bin/bash
source vm2.config
export $(cut -d= -f1 vm2.config)

echo "Raising internal IP"
ip link set up $INTERNAL_IF
echo "Inserting VLAN module"
modprobe 8021q
echo "Adding VLAN"
vconfig add $INTERNAL_IF $VLAN
echo "Adding VLAN IP"
ip addr add $APACHE_VLAN_IP dev $INTERNAL_IF.$VLAN
echo "Raising VLAN"
ip link set up $INTERNAL_IF.$VLAN
echo "Setting gateway"
ip route add default via $GW_IP

IS_APACHE_INSTALLED=$(dpkg -l apache2 | grep ii |wc -l)

if [ $IS_APACHE_INSTALLED = 0 ]
then
        echo "Apache is absent, installing"
        echo "Updating apt"
        apt update
        echo "Installing apache2"
        apt install apache2 -y -q
        echo "Setting Apache site"
        envsubst < 0-default.conf '$APACHE_VLAN_IP' > /etc/apache2/sites-enabled/0-default.conf
        echo "Restarting Apache"
        systemctl restart apache2
else
        echo "Apache installed earlier"
fi
