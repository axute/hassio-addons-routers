#!/bin/bash

# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
reset_interfaces(){
    ifdown $INTERFACE
    sleep 1
    ip link set $INTERFACE down
    ip addr flush dev $INTERFACE
}

term_handler(){
    echo "Resseting interfaces"
    reset_interfaces
    echo "Stopping..."
    exit 0
}

# Setup signal handlers
trap 'term_handler' SIGTERM

echo "Starting..."

CONFIG_PATH=/data/options.json

SSID=$(jq --raw-output ".ssid" $CONFIG_PATH)
WPA_PASSPHRASE=$(jq --raw-output ".wpa_passphrase" $CONFIG_PATH)
CHANNEL=$(jq --raw-output ".channel" $CONFIG_PATH)
ADDRESS=$(jq --raw-output ".address" $CONFIG_PATH)
NETMASK=$(jq --raw-output ".netmask" $CONFIG_PATH)
BROADCAST=$(jq --raw-output ".broadcast" $CONFIG_PATH)
INTERFACE=$(jq --raw-output ".interface" $CONFIG_PATH)
INTERNET_IF=$(jq --raw-output ".internet_interface" $CONFIG_PATH)
ALLOW_INTERNET=$(jq --raw-output ".allow_internet" $CONFIG_PATH)
ALLOW_INTERNET_IP_ADDRESSES=$(jq --raw-output '.allow_internet_ip_addresses | join(" ")' $CONFIG_PATH)
HIDE_SSID=$(jq --raw-output ".hide_ssid" $CONFIG_PATH)
STATIC_LEASES=$(jq --raw-output '.static_leases | join(" ")' $CONFIG_PATH)
COUNTRY_CODE=$(jq --raw-output ".country_code" $CONFIG_PATH)

DHCP_SERVER=$(jq --raw-output ".dhcp_enable" $CONFIG_PATH)
DHCP_START=$(jq --raw-output ".dhcp_start" $CONFIG_PATH)
DHCP_END=$(jq --raw-output ".dhcp_end" $CONFIG_PATH)
DHCP_DNS=$(jq --raw-output ".dhcp_dns" $CONFIG_PATH)
DHCP_SUBNET=$(jq --raw-output ".dhcp_subnet" $CONFIG_PATH)
DHCP_ROUTER=$(jq --raw-output ".dhcp_router" $CONFIG_PATH)

NTP_SERVER=$(jq --raw-output ".ntp_enable" $CONFIG_PATH)

# Enforces required env variables
required_vars=(SSID WPA_PASSPHRASE CHANNEL ADDRESS NETMASK BROADCAST)
for required_var in "${required_vars[@]}"; do
    if [[ -z ${!required_var} ]]; then
        echo >&2 "Error: $required_var env variable not set."
        exit 1
    fi
done


INTERFACES_AVAILABLE="$(ifconfig -a | grep wl | cut -d ' ' -f '1')"
UNKNOWN=true

if [[ -z ${INTERFACE} ]]; then
        echo >&2 "Network interface not set. Please set one of the available:"
        echo >&2 "${INTERFACES_AVAILABLE}"
        exit 1
fi

for OPTION in ${INTERFACES_AVAILABLE}; do
    if [[ ${INTERFACE} == ${OPTION} ]]; then
        UNKNOWN=false
    fi 
done

if [[ ${UNKNOWN} == true ]]; then
        echo >&2 "Unknown network interface ${INTERFACE}. Please set one of the available:"
        echo >&2 "${INTERFACES_AVAILABLE}"
        exit 1
fi

echo "Set nmcli managed no"
nmcli dev set ${INTERFACE} managed no

echo "Network interface set to ${INTERFACE}"

# Configure iptables to enable/disable internet
RULE_3="POSTROUTING -o ${INTERNET_IF} -j MASQUERADE"
RULE_4="FORWARD -i ${INTERNET_IF} -o ${INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT"
RULE_5="FORWARD -i ${INTERFACE} -o ${INTERNET_IF} -j ACCEPT"
RULE_6="FORWARD -i ${INTERFACE} -o ${INTERNET_IF}  -s #IP_ADDR# -j ACCEPT"
RULE_7="FORWARD -i ${INTERFACE} -o ${INTERNET_IF} -j DROP"

echo "Deleting iptables"
iptables -v -t nat -D $(echo ${RULE_3})
iptables -v -D $(echo ${RULE_4})
if [ ${#ALLOW_INTERNET_IP_ADDRESSES} -ge 1 ]; then
    ALLOWED=($ALLOW_INTERNET_IP_ADDRESSES)
    for ip_addr in "${ALLOWED[@]}"; do
        echo iptables -v -D $(echo ${RULE_6/\#IP_ADDR\#/"$ip_addr"})
    done
    echo iptables -v -D $(echo ${RULE_7})
else
    echo iptables -v -D $(echo ${RULE_5})
fi

if test ${ALLOW_INTERNET} = true; then
    echo "Configuring iptables for NAT"
    iptables -v -t nat -A $(echo ${RULE_3})
    iptables -v -A $(echo ${RULE_4})
    if [ ${#ALLOW_INTERNET_IP_ADDRESSES} -ge 1 ]; then
        ALLOWED=($ALLOW_INTERNET_IP_ADDRESSES)
        for ip_addr in "${ALLOWED[@]}"; do
            echo iptables -v -A $(echo ${RULE_6/\#IP_ADDR\#/"$ip_addr"})
        done
        echo iptables -v -A $(echo ${RULE_7})
    else
        echo iptables -v -A $(echo ${RULE_5})
    fi
fi


# Setup hostapd.conf
HCONFIG="/hostapd.conf"

echo "Setup hostapd ..."
echo "ssid=${SSID}" >> ${HCONFIG}
echo "wpa_passphrase=${WPA_PASSPHRASE}" >> ${HCONFIG}
echo "channel=${CHANNEL}" >> ${HCONFIG}
echo "interface=${INTERFACE}" >> ${HCONFIG}
echo "" >> ${HCONFIG}

if test ${HIDE_SSID} = true; then
    echo "Hidding SSID"
    echo "ignore_broadcast_ssid=1" >> ${HCONFIG}
fi

if [[ ${COUNTRY_CODE} != null ]]; then
    echo "country_code=${COUNTRY_CODE}" >> ${HCONFIG}
fi

# Setup interface
IFFILE="/etc/network/interfaces"

echo "Setup interface ..."
echo "" > ${IFFILE}
echo "iface ${INTERFACE} inet static" >> ${IFFILE}
echo "  address ${ADDRESS}" >> ${IFFILE}
echo "  netmask ${NETMASK}" >> ${IFFILE}
echo "  broadcast ${BROADCAST}" >> ${IFFILE}
echo "" >> ${IFFILE}

echo "Resseting interfaces"
reset_interfaces
ifup ${INTERFACE}
sleep 1

if test ${DHCP_SERVER} = true; then
    # Setup hdhcpd.conf
    UCONFIG="/etc/udhcpd.conf"

    echo "Setup udhcpd ..."
    echo "interface    ${INTERFACE}"     >> ${UCONFIG}
    echo "start        ${DHCP_START}"    >> ${UCONFIG}
    echo "end          ${DHCP_END}"      >> ${UCONFIG}
    echo "opt dns      ${DHCP_DNS}"      >> ${UCONFIG}
    echo "opt subnet   ${DHCP_SUBNET}"   >> ${UCONFIG}
    echo "opt router   ${DHCP_ROUTER}"   >> ${UCONFIG}
    if [ ${#STATIC_LEASES} -ge 1 ]; then
        LEASES=($STATIC_LEASES)
        for entry in "${LEASES[@]}"; do
            echo "static_lease" $(echo ${entry/=/" "})   >> ${UCONFIG}
        done
    fi
    echo ""                              >> ${UCONFIG}

    echo "Starting DHCP server..."
    udhcpd -f &
fi

if test ${NTP_SERVER} = true; then
    pidfile="/var/run/chronyd.pid"

    if [ -f "$pidfile" ]
    then
        rm $pidfile
    fi

    echo "Starting NTP server..."
    exec /usr/sbin/chronyd -d -f /var/lib/chrony/chrony.conf &
fi


sleep 1

echo "Starting HostAP daemon ..."
hostapd ${HCONFIG} &

while true; do 
    echo "Interface stats:"
    ifconfig | grep ${INTERFACE} -A6
    sleep 3600
done
