#!/bin/bash

# Any configurable values should be up here, kthx
DEFAULT_TZ=America/Chicago
OPENRESTY_VERSION=1.21.4.1

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
    echo "You really should run this script as the 'pi' user."
    exit 1
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
UPDATED=0
for possibleDir in . .. ../images images
do
    if [[ -e "$possibleDir/splash.png" ]]
    then
        sudo cp images/splash.png /usr/share/plymouth/themes/pix/splash.png
        UPDATED=1
    fi
done
if [[ "$UPDATED" ==  "0" ]]
then 
    echo "!!! I don't see the splash screen, so you should check on that. I won't stop the install though."
fi 
echo " "

echo "* setting up .xinitrc for screen blanking"
mkdir -p ~/.config/lxsession/LXDE-pi/
cat <<FOO | tee  mkdir -p ~/.config/lxsession/LXDE-pi/autostart
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

echo ".. downloading version $OPENRESTY_VERSION"
wget --quiet "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz"
if [[ ! -e "openresty-${OPENRESTY_VERSION}.tar.gz" ]]
then
    echo "For some reason the openresety file wasn't downloaded. Stopping."
    exit 1
fi
echo ".. unpacking"
if ! tar zxf "openresty-${OPENRESTY_VERSION}.tar.gz" --directory /tmp --one-top-level=oresty-$$ 
then
    echo "Extracting the archive caused an error."
    exit 1
fi

echo ".. building and installing"
OLDDIR="$PWD"
cd /tmp/oresty-$$ || exit 1
if ! ./configure -j2 && make -j2 && sudo make install
then
    echo "openresty build failed"
    exit 1
fi
cd "$OLDDIR" || exit 1

echo ".. adding openresty directories to PATH"
echo "export PATH=/usr/local/openresty/nginx/bin:/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:\$PATH" >> ~/.profile
echo " "

echo "* creating wifi config files"

cat << EOF | sudo tee /etc/hostapd/hostapd.conf
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

echo "* creating hotspot control script"
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
        echo "    hotspot on -- turn on the hotspot"
        echo "    hotspot off -- turn off the hotspot"
        echo ""
        echo "That's all for now."
        echo ""
    ;;
esac
EOF

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

# set up XBMs
# "http://torinak.com/font/7segment.ttf"
#
# copy nginx config files
#
# 