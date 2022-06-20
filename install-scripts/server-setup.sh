#!/bin/bash
#
# Check various server settings
#
# - time zone set up (defaults to Chicago TZ)
# - apt packages needed to build & run the timer software
# - turn off screen blanking
# - confirm that Python 3 is default version
#
#

TIMEZONE=America/Chicago

if [ "$DISPLAY" = "" ]
then
	echo "! DISPLAY var is not set, so I'll set it to :0"
	export DISPLAY=:0
fi


echo "Checking server setup"

echo ".. time zone"
if [[ -e /etc/timezone ]]
then

	foo=$(cat /etc/timezone)
	echo "Current timezone is: $foo"
	if [ "$foo" != "$TIMEZONE" ]
	then
		echo "! Time zone is not $TIMEZONE"
		read -p -r "Do you want me to take care of that for you? [Yn] " yn
		case $yn in
			[nN] ) echo "Ok den.";;
			* ) sudo echo $TIMEZONE > /etc/timezone;;
		esac
	else
		echo "Great, it's $TIMEZONE as expected."
	fi
else
	echo "/etc/timezone doesn't exist."
	read -p -r "Do you want me to take care of that for you? [Yn] " yn
	case $yn in
		[nN] ) echo "Ok den.";;
		* ) sudo echo $TIMEZONE > /etc/timezone
			echo "Set time zone to $TIMEZONE.";;
	esac
fi


echo ".. apt package updates"
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install libpcre3-dev libssl-dev perl make build-essential curl redis python3-tk python3-requests fonts-ubuntu hostapd dnsmasq imagemagick -y


echo ".. turning off screen blanking"
xset s off && xset dpms 0 0 0 && xset dpms force on

echo ".. checking python version"
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
  fi
fi

echo "done."


