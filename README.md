# 20x2 Chicago Clock server 

This is everything you need to set up a Raspberry Pi as a 20x2 clock server. As much stuff as possible is going to be scripted out, so that a basic Raspberry Pi can be turned into a [20x2 Chicago](http://www.20x2chi.org/) clock server. 

## What's going on here

This is an application to set up a Raspberry Pi server as a timer. Due to the unique requirements for the timer we use, this is the latest version of a long-running project to provide a usable timer with minimal points of failure.

Until recently the server was controlled remotely with, and displayed the time on, Arduino-based remote clients, but a catastrophic failure of the Arduino libraries used for controlling LCD displays has made that technology much less reliable. The Arduino remote is still viable, thanks to the [M5Stack](http://www.m5stack.com/) IoT platforms. 

So the current plan is: set up a Raspberry Pi server with a composite monitor (or rather multiple monitors connected using consumer-grade composite video distribution/amplifier products); use the Arduino remote to control the timer; and set up the screens on stage to be visible to the speakers.

## Technologies used

This server is designed to run on a vanilla Raspberry Pi desktop install. The stuff that will be built and installed:
* [OpenResty](https://openresty.org/en/installation.html) (Nginx dev tool with Lua scripting, used for the API)
* [Redis](https://redis.io/docs/getting-started/installation/install-redis-on-linux/) (in-memory database store)
* [Tkinter](http://tkdocs.com/) (Python interface for Tk)
* [hostapd](https://w1.fi/hostapd/) (host AP daemon for creating wifi hotspot)
* [dnsmasq](https://wiki.archlinux.org/title/dnsmasq) (for DHCP)

## Directories

* admin-scripts/ -- Scripts used to set up administration of the server
* arduino/ -- Arduino admin client code (TODO)
* images/ -- XBM files used to display the digits on the Tk canvas
* install-scripts/ -- Scripts used to set up the RPi server configuration for use
* nginx/ -- This is the Nginx config file that serves up the API using Redis
  
## License
Distributed under the MIT License. See `LICENSE.txt` for more information.

## Contact
James Allenspach

james.allenspach@gmail.com

Project home: https://github.com/manminusone/20x2-clock-7
