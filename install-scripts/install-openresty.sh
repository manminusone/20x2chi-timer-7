#!/bin/bash

VERSION=1.21.4.1

if [[ -d openresty-${VERSION} ]]
then
	read -p -r "Looks like the openresty directory exists. Do you want to use it? [yN] " yn
	case $yn in
		[yY] ) echo "Ok den.";;
		* ) echo .. deleting existing content
			rm -rf openresty-${VERSION}*;;
	esac
fi

echo Installing OpenResty
if [[ ! -e openresty-${VERSION}.tar.gz ]]
then
	echo .. downloading version $VERSION
	wget --quiet https://openresty.org/download/openresty-${VERSION}.tar.gz
	if [[ ! -e openresty-${VERSION}.tar.gz ]]
	then
		echo "For some reason the openresety file wasn't downloaded. Stopping."
		exit 1
	fi
fi

if [[ ! -d openresty-${VERSION} ]]
then 
	echo .. unpacking
	tar zxf openresty-${VERSION}.tar.gz
fi

cd openresty-${VERSION}.tar.gz || exit
./configure -j2 && make -j2 && sudo make install

echo ".. saving PATH updates"
echo 'export PATH=/usr/local/openresty/nginx/bin:/usr/local/openresty/bin:/usr/local/openresty/nginx/sbin:$PATH' >> ~/.profile
echo "done."

