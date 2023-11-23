#!/bin/bash

# CHANGE THESE TO FIT YOUR NEEDS
allowed_ips="xxx.xxx.xxx.xxx/xx, yyy.yyy.yyy.yyy/yy, zzz.zzz.zzz.zzz/zz"
endpoint="example.com:51820"
config_filename="/etc/wireguard/vpn.conf"
network_address="aaa.bbb.ccc.ddd"

# ---------- Script begins here ----------
if [[ $(id -u) != 0 ]]
then
	echo "Please run this script as sudo, since the config file most likely has restricted permissions"
	exit
fi
if [[ !  $(which wg-quick 2> /dev/null) ]]
then
	echo "Please install the wireguard tools and setup your server config before trying again"
	exit
fi
if [[ ! -f $config_filename ]]
then
	echo "Make sure that the server config file exists and is working before trying again"
	exit
fi
if [[ -z $(which qrencode 2> /dev/null) ]]
then
	if [[ ! -z $(which dnf 2> /dev/null) ]]
	then
		if [[ ! -z $(dnf search qrencode -q) ]]
		then
			echo "This script requires qrencod, do you want to install it? [y/N]"
			read user_input
			if [[ $user_input =~ y|yes ]]
			then
				dnf install qrencode -y
				installed="yes"
			fi
		fi
	fi
	if [[ -z $installed ]]
	then
		echo "This script requires qrencode, please install it before trying again."
		exit
	fi
fi

privkey=$(wg genkey)
pubkey=$(wg pubkey <<< $privkey)
server_privkey=$(sed -n "s/PrivateKey\s*=\s*//p" $config_filename)
server_pubkey=$(wg pubkey <<< $server_privkey)
network_address=$(sed "s/\.[0-9]*$//" <<< $network_address)
valid_addresses=$(seq 2 1 200)
addresses=$(sed -n "s/AllowedIPs\s*=\s*[0-9]*\.[0-9]*\.[0-9]*\.\([0-9]*\)\/.*/\1/p" $config_filename)
device_address=$(echo $addresses $valid_addresses | tr " " "\n" | sort -g | uniq -u | head -n 1)
address=$network_address.$device_address

config=$(cat << EOM
[Interface]
PrivateKey = $privkey
Address = $address/32
DNS = 1.1.1.1

[Peer]
PublicKey = $server_pubkey
AllowedIPs = $network_address.0/24, $allowed_ips
Endpoint = $endpoint
EOM
)

shown=""
while :
do
cat << EOM
Select action:
[q] Display QR-code
[t] Display config
[c] Continue
EOM

read user_input


case $user_input in
	"q")
		qrencode -t UTF8i <<< $config
		shown="yes"
		;;
	"t")
		echo ""
		cat <<< $config
		shown="yes"
		echo ""
		;;
	"c")
		if [[ ! -z $shown ]]
		then
			break
		fi
		echo "You didn't view the config, aborting."
		exit
		;;
esac
done


echo "Want to add this peer to config? [y/N]"

read user_input

if [[ $user_input =~ y|yes ]]
then
	echo "Please enter a name for the new peer:"
	read comment
	server_config=$(cat << EOM

# $comment
[Peer]
PublicKey = $pubkey
AllowedIPs = $address/32
EOM
)
	tee -a $config_filename <<< $server_config > /dev/null
	echo "Do you want to restart the wg-quick service? [y/N]"
	read user_input
	if [[ $user_input =~ y|yes ]]
	then
		target=$(sed "s/.*\/\([a-zA-Z0-9]*\)\.conf$/\1/" <<< $config_filename)
		systemctl restart wg-quick@$target
		echo "Service restarted."
	fi
fi

