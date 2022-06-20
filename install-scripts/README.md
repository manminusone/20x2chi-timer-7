# Installation scripts

This directory contains helper scripts used to initialize the Raspberry Pi server for running the 20x2 clock timer.

* generate-digits.sh -- This is a bash script that you can use to generate your own digit XBM images for use in the display. You will need to provide your own monospace font for generating the digit images. Make sure you have [ImageMagick](http://www.imagemagick.org/) and Perl installed. (The first one is less likely to come installed on RPi than the second.)
* install-openresty.sh -- This will install the OpenResty server for you. Nothing too complex, but it's good to have it automatically set up for you.
* post-receive -- This is a Git post-receive script that will be used to deploy code changes to the RPi server via git. TODO

