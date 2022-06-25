#!/bin/bash
#
#
# Arguments:
#
# --reinstall    : force reinstall of all items
# --no-reinstall : do no reinstalls
#


# Any configurable values should be up here, kthx
DEFAULT_TZ=America/Chicago
OPENRESTY_VERSION=1.21.4.1

SSID="TestSSID"
PASSWD="ChangeThisPassword"


# this is all in a function because it can be called in a couple of places
install_openresty() {
    echo ".. downloading version $OPENRESTY_VERSION"
    wget -nc --quiet "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz"
    if [[ ! -e "openresty-${OPENRESTY_VERSION}.tar.gz" ]]
    then
        echo "For some reason the openresety file wasn't downloaded. Stopping."
        exit 1
    fi
    echo ".. unpacking"
    if ! tar zxf "openresty-${OPENRESTY_VERSION}.tar.gz" --directory /tmp
    then
        echo "Extracting the archive caused an error."
        exit 1
    fi

    echo ".. building and installing"
    OLDDIR="$PWD"
    cd "/tmp/openresty-${OPENRESTY_VERSION}" || exit 1
    if ! ./configure -j2
    then
        echo "openresty configure failed"
        exit 1
    fi
    if ! make -j2
    then
        echo "openresty make failed"
        exit 1
    fi
    if ! sudo make install
    then
        echo "openrest install failed"
        exit 1
    fi
    cd "$OLDDIR" || exit 1

	echo ".. adding systemd script"
	cat <<- EOF | sudo tee /etc/systemd/system/openresty.service > /dev/null
	# Stop dance for OpenResty
	# =========================
	#
	# ExecStop sends SIGSTOP (graceful stop) to OpenResty's nginx process.
	# If, after 5s (--retry QUIT/5) nginx is still running, systemd takes control
	# and sends SIGTERM (fast shutdown) to the main process.
	# After another 5s (TimeoutStopSec=5), and if nginx is alive, systemd sends
	# SIGKILL to all the remaining processes in the process group (KillMode=mixed).
	#
	# nginx signals reference doc:
	# http://nginx.org/en/docs/control.html
	#
	[Unit]
	Description=The OpenResty Application Platform
	After=syslog.target network-online.target remote-fs.target nss-lookup.target
	Wants=network-online.target

	[Service]
	Type=forking
	PIDFile=/usr/local/openresty/nginx/logs/nginx.pid
	ExecStartPre=/usr/local/openresty/nginx/sbin/nginx -t -q -g 'daemon on; master_process on;'
	ExecStart=/usr/local/openresty/nginx/sbin/nginx -g 'daemon on; master_process on;'
	ExecReload=/usr/local/openresty/nginx/sbin/nginx -g 'daemon on; master_process on;' -s reload
	ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /usr/local/openresty/nginx/logs/nginx.pid
	TimeoutStopSec=5
	KillMode=mixed

	[Install]
	WantedBy=multi-user.target
	EOF
	sudo systemctl daemon-reload
	sudo systemctl enable openresty
	echo ".. attempting startup of openresty service"
	if ! sudo systemctl start openresty
	then
		echo "Startup failed. Try 'systemctl status openresty' to see what went wrong."
		exit 1
	fi
	echo " "	


    # don't add the PATH update if it appears to be in .profile
    if [[ $(grep -c openresty ~/.profile) == "0" ]]
    then
        echo ".. adding openresty directories to PATH"
        echo "export PATH=/usr/local/openresty/nginx/bin:/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:\$PATH" >> ~/.profile
    fi
    echo " "
}

install_wifi_config() {
	cat <<- EOF | sudo tee /etc/hostapd/hostapd.conf > /dev/null
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

	# also need to update the script to use this config file
	if ! sudo sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' /etc/default/hostapd
	then
		echo "sed command to update /etc/hostapd/hostapd.conf failed, which I wasn't expecting."
		exit 1
	fi

	cat <<- EOF | sudo tee /etc/dhcpcd.conf.ORIGINAL > /dev/null
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
	cat <<- EOF | sudo tee -a /etc/dhcpcd.conf.HOTSPOT > /dev/null

	interface wlan0
	static ip_address=192.168.4.1/24
	denyinterfaces wlan0
	EOF

	cat <<- EOF | sudo tee /etc/dnsmasq.conf.ORIGINAL > /dev/null
	dhcp-mac=set:client_is_a_pi,B8:27:EB:*:*:*
	dhcp-reply-delay=tag:client_is_a_pi,2

	EOF
	sudo cp /etc/dnsmasq.conf.ORIGINAL /etc/dnsmasq.conf.HOTSPOT
	cat <<- EOF | sudo tee -a /etc/dnsmasq.conf.HOTSPOT > /dev/null
	interface=wlan0
	dhcp-range=192.168.4.5,192.168.4.20,255.255.255.0,24h
	EOF

	echo "* creating hotspot control script"
	cat <<- EOF | sudo tee /usr/local/bin/hotspot > /dev/null
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
			echo "    hotspot on -- turn on the hotspot"
			echo "    hotspot off -- turn off the hotspot"
			echo ""
			echo "That's all for now."
			echo ""
		;;
	esac
	EOF
	sudo chmod a+x /usr/local/bin/hotspot
}

gen_xbm() {
	echo " "
	wget -q -nc 'http://torinak.com/font/7segment.ttf'
	tempdir=$(dirname "$0")
	if [[ ! -e "$tempdir/generate-digits.sh" ]]
	then
		echo "I don't see the generate-digits.sh script around here."
		exit 1
	fi

	/bin/bash "$tempdir/generate-digits.sh" -f 7segment.ttf -d "$1"
}

# check arguments

REINSTALL=""
for arg in "$@"
do
	case $arg in 
		--reinstall    ) REINSTALL="y";;
		--no-reinstall ) REINSTALL="n";;
		* ) ;;
	esac
done

# this should be a safe value to use
export DISPLAY=:0

echo "@@@@@    @  @@@@@    @  @@@@@@@@@@  @@@    @@@"
echo "@@@@@@@@@   @@@@ @@@@   @@@@@@@@@@  @@@@@@@ @@"
echo "@@@@@@@@@   @@@@ @@@@   @@ @@@ @@@  @@@@@@@ @@"
echo "@@@@@@@  @  @@@@ @@@@   @@@ @ @@@@  @@@@@  @@@"
echo "@@@@@  @@@  @@@@ @@@@   @@@@ @@@@@  @@@  @@@@@"
echo "@@@@@       @@@@ @@@@   @@@ @ @@@@  @@@     @@"
echo "@@@@@@@@@@  @@@@@    @  @@ @@@ @@@  @@@@@@@@@@"
echo ""
echo "           20x2 Chicago Timer Setup"
echo ""

read -r -p "Hit Enter to begin server setup process: " yn

DISTID=$(lsb_release -i)

if [[ "$DISTID" != *"Raspbian"* ]]
then
    echo "Expecting to run this on Raspbian."
    exit 1
fi

if [[ "$USER" != "pi" ]]
then
    echo "You should run this script as the 'pi' user."
    exit 1
fi

# Make sure you are in an appropriate directory
if [[ ! -e python-timer.py ]]
then
	if [[ ! -e ../python-timer.py ]]
	then
		echo "You should make sure you are in the 20x2-timer-7 repo when you setup"
		echo "because there are some files copied over and created."
		echo " "
		echo "So please locate the repo and run the setup.sh script there."
		exit 1
	else
		cd ..
	fi
fi

if [[ -e /run/sshwarn ]]
then
    echo "You haven't changed the default password for the 'pi' user."
    read -r -p "Do you want to change the password before we start? [Yn] " yn
    case $yn in
      [nN]* ) echo "Okay, just remember to change it please? Thanks.";;
      * ) /usr/sbin/passwd ;
    esac
fi

echo "Part 1: System Setup"
echo " "

echo "* updating apt packages"
sudo apt-get update
if ! sudo apt-get upgrade -y
then
    echo "The upgrade threw an error. Check it out, won't you?"
    exit 1
fi
echo "* installing required software"
if ! sudo apt-get install libpcre3-dev libssl-dev perl make build-essential curl redis python3-tk python3-requests vim imagemagick hostapd dnsmasq fonts-dseg -y
then
    echo "The software install threw an error. Check that out please."
    exit 1
fi
echo " "

echo "* checking time zone"
CHECKTZ=$(cat /etc/timezone)
if [[ "$CHECKTZ" != "$DEFAULT_TZ" ]]
then
    echo "Your time zone is set to: $CHECKTZ"
    echo "Should I set it to $DEFAULT_TZ for you? "
    read -rp "[Yn] " yn 

    case "$yn" in 
        [Nn]* )
            echo "OK, leaving it alone.";;
        * )
            echo "Updating"
            echo $DEFAULT_TZ | sudo tee /etc/timezone
            ;;
    esac
fi
echo " "

echo "* updating /boot/config.txt for composite video output"
sudo sed -i 's/#\?hdmi_force_hotplug=.\+/hdmi_ignore_hotplug=1/g' /boot/config.txt
sudo sed -i 's/#\?sdtv_mode=.\+/sdtv_mode=0/g' /boot/config.txt
echo " "

echo "* updating the default desktop background to black.png"
convert -size 720x480 canvas:black black.png
sudo mv black.png /etc/alternatives/desktop-background
echo " "

echo "* updating the splash screen"
if [[ -e images/splash.png ]]
then
	if ! sudo cp images/splash.png /usr/share/plymouth/themes/pix/splash.png 
	then
		echo "! Copying the splash.png file to the /usr/share/plymouth/themes/pix directory failed"
		exit 1
	fi
	UPDATED=1
fi

if [[ "$UPDATED" ==  "0" ]]
then 
    echo "!!! I don't see the splash screen, so you should check on that. I won't stop the install though."
fi 
echo " "

echo "* setting up .xinitrc for screen blanking"
mkdir -p ~/.config/lxsession/LXDE-pi/
cat <<FOO | tee  ~/.config/lxsession/LXDE-pi/autostart > /dev/null
@lxpanel --profile LXDE
@pcmanfm --desktop --profile LXDE

@xset s noblank
@xset s off
@xset -dpms
FOO
echo " "

echo "Part 2: Software Setup"
echo " "
echo "* setting up openresty"

if [[ -d /usr/local/openresty ]]
then
	if [[ "$REINSTALL" != "" ]]
	then
		yn="$REINSTALL"
	else
		echo "Looks like it already has been installed."
		read -r -p "Should I reinstall? [yN] " yn
	fi
    case $yn in 
    [yY]* ) 
        echo "OK, reinstalling."
        install_openresty;;
    * )  ;;
    esac
else
    install_openresty
fi


echo "* creating wifi config files"

if [[ -e /etc/dhcpcd.conf.HOTSPOT ]]
then
	if [[ "$REINSTALL" != "" ]]
	then
		yn="$REINSTALL"
	else
		echo "Looks like it already has been installed."
		read -r -p "Should I reinstall? [yN] " yn
	fi
	case $yn in
		[yY]* )
			echo "OK, reinstalling."
			install_wifi_config;;
		* ) ;;
	esac
else
	install_wifi_config
fi


echo "* checking default python version"
foo=$(python -V)
if [[ "$foo" == *"Python 3"* ]]
then
  echo ".. default python is 3.x, so we are good."
else
  echo ".. Python should be version 3. Updating the symlink."
  sudo rm /usr/bin/python
  sudo ln -s /usr/bin/python3 /usr/bin/python
  foo=$(python -V)
  if [[ "$foo" == *"Python 3"* ]]
  then
    echo ".. yaay, that worked"
  else 
    echo ".. ! default Python is still not 3. Check your PATH variable."
    exit 1
  fi
fi
echo " "

echo "* creating XBMs"

if [[ $(find images -name '*.xbm' | wc -l) != "0" ]]
then
	if [[ "$REINSTALL" != "" ]]
	then
		yn="$REINSTALL"
	else
		echo "Looks like it already has been installed."
		read -r -p "Should I reinstall? [yN] " yn
	fi
	case $yn in 
		[yY]* ) echo "OK, reinstalling."
			gen_xbm images ;;
		* ) ;;
	esac
else
	gen_xbm images
fi
echo " "

# copy nginx config files

echo "* copying nginx files to /usr/local/openresty"
if ! sudo cp -R nginx /usr/local/openresty
then
	echo "Copy didn't work"
	exit 1
fi
echo " "

# set up python script to run at startup
echo "* setting up python-timer.py to run at desktop startup"
mkdir -p  /home/pi/.config/autostart
cat <<EOF  > /home/pi/.config/autostart/timer.desktop
[Desktop Entry]
Type=Application
Name=20x2 Timer
Exec=/usr/bin/python3 $PWD/python-timer.py
EOF
echo " "

echo " *** done ***"
echo " Now restart."
exit 0
