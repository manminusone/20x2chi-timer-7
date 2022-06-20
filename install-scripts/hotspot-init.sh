#!/bin/bash
#
# hotspot-init.sh -- create the appropriate config files and scripts for hotspot configuration
#

# EDIT THESE VALUES
SSID="SSIDNAME"
PASSWD="PASSWORD"



shouldbe() {
	foo=$($1)
	if [[ "$foo" != *"$2"* ]]
	then
		echo "$3 is incorrect version (expecting $2)"
		exit 1
	fi
}


create_conf() {
	# creating the basic config files
	cat <<- EOF | sudo tee /etc/hostapd/hostapd.conf
	interface=wlan0
	bridge=br0
	hw_mode=g
	channel=7
	wmm_enabled=0
	macaddr_acl=0
	auth_algs=1
	ignore_broadcast_ssid=0
	wpa=2
	wpa_key_mgmt=WPA-PSK
	wpa_pairwise=TKIP
	rsn_pairwise=CCMP
	ssid=$SSID
	wpa_passphrase=$PASSWD
	EOF
	cat <<- EOF | sudo tee /etc/dhcpcd.conf.ORIGINAL
	hostname 20x2chi-timer
	clientid
	persistent
	option rapid_commit
	option domain_name_servers, domain_name, domain_search, host_name
	option classless_static_routes
	option interface_mtu
	require dhcp_server_identifier
	slaac private
	EOF
	sudo cp /etc/dhcpcd.conf.ORIGINAL /etc/dhcpcd.conf.HOTSPOT
	cat <<- EOF | sudo tee -a /etc/dhcpcd.conf.HOTSPOT
	
	interface wlan0
	static ip_address=192.168.4.1/24
	denyinterfaces wlan0
	EOF

	cat <<- EOF | sudo tee /etc/dnsmasq.conf.ORIGINAL
	dhcp-mac=set:client_is_a_pi,B8:27:EB:*:*:*
	dhcp-reply-delay=tag:client_is_a_pi,2

	EOF
	sudo cp /etc/dnsmasq.conf.ORIGINAL /etc/dnsmasq.conf.HOTSPOT
	cat <<- EOF | sudo tee -a /etc/dnsmasq.conf.HOTSPOT
	interface=wlan0
	dhcp-range=192.168.4.5,192.168.4.20,255.255.255.0,24h
	EOF
}

create_hotspot_script() {
	cat <<- EOF > sudo tee /usr/local/bin/hotspot
	#!/bin/bash
	#
	# This is a control script to set up the hotspot configs. 
	#
	# You should first run the hotspot-init.sh script to set up the hotspot,
	# and then use 'hotspot on' and 'hotspot off' to control the functionality.
	#
	#

	stop_services() {
		sudo systemctl stop hostapd
		sudo systemctl stop dnsmasq
	}


	activate_services() {
		sudo systemctl unmask hostapd
		sudo systemctl enable hostapd
		sudo systemctl enable dnsmasq
	}

	deactivate_services() {
		sudo systemctl disable hostapd
		sudo systemctl mask hostapd
	}

	turnon() {
		echo cp "\${1}.HOTSPOT" "\$1"
		sudo cp "\${1}.HOTSPOT" "\$1"
	}

	turnoff() {
		echo cp "\${1}.ORIGINAL" "\$1"
		sudo cp "\${1}.ORIGINAL" "\$1"
	}

	###
	###	main code
	###

	case \$1 in 
		on )
			echo "turning on"
			stop_services
			turnon /etc/dhcpcd.conf
			turnon /etc/dnsmasq.conf
			activate_services
			echo "Rebooting..."
			sudo reboot now
		;;

		off )
			echo "turning off"
			stop_services
			turnoff /etc/dhcpcd.conf
			turnoff /etc/dnsmasq.conf
			deactivate_services
			echo "Rebooting..."
			sudo reboot now
		;;
		* )
			echo "Command usage:"
			echo ""
			echo "    hotspot init -- create the config files for hotspot control"
			echo "    hotspot on -- turn on the hotspot"
			echo "    hotspot off -- turn off the hotspot"
			echo ""
			echo "That's all for now."
			echo ""
		;;
	esac
	EOF
}

# main code

if [[ "$PASSWD" == "PASSWORD" ]]
then
	echo You need to edit this script.
	echo Replace the default values of SSID and PASSWD at the top of the script.
	exit 1
fi
echo "Checking versions of required software"
echo -n ".. dnsmasq ... "
shouldbe "/usr/sbin/dnsmasq -v" "2.80" "dnsmasq"
echo "OK"
echo -n ".. dhcpcd ... "
shouldbe "/usr/sbin/dhcpcd --version" "8.1.2" "dhcpcd"
echo "OK"

if [[ -e /etc/dnsmasq.conf.HOTSPOT  ]]
then
	echo "!!! It looks like this script has already been run."
	read -p -r "Run again? [yN] " yn
	case $yn in
		[yY] ) echo "OK, will do";;
		* ) echo "Cool. exiting"
			exit 0;;
	esac
	echo "Creating config files"
	create_conf
	create_hotspot_script
	echo "done."
fi

