#!/usr/bin/python3
#
# The main Tk program to display the timer.
# 
# HTTP requests to the localhost:80 HTTP server are made to get the current time value.
# This is displayed using a series of XBM files stored in the images/ directory, to make
# it easier to draw digits. See the admin script generate-digits.sh for details on
# how to make your own digits.
#

from tkinter import *
from requests.sessions import Session
import json
import os
from os.path import exists
import configparser
import glob
import re
import time
import logging

logging.basicConfig(level=logging.DEBUG,filename="/tmp/timer-log.txt",format='%(msecs)d %(levelname)s %(name)s %(message)s')

# Set this flag to False if you want to run locally w/o API server
HTTPREQ = True

# OFFBKGCOL: the background color of the timer when it's off
OFFBKGCOL = '#060'
# BKGCOL: a dict of second values and times. The first matching one is the color used (smallest values read first)
BKGCOL = { 0: 'red', 15: 'yellow', 120: 'green' }
# TXTCOL: the value of the text (will likely be black for any color config)
TXTCOL = 'black'
# PREFIX: the prefix for XBM files used in the display (this may be changed, but it's not easy to change out in the field)
PREFIX='7seg'
# set the DISPLAY value if not present
if "DISPLAY" not in os.environ:
  os.environ["DISPLAY"] = ':0'

# some globals
secs=0
timeron = False

# detect fonts
fontconfig = configparser.ConfigParser()
if not(exists("images/digits.ini")):
  logging.info("Generating digits.ini from current images directory")
  files = glob.glob("images/*-colon-*.xbm")
  for f in files:
    m = re.match("images/(.+)\-colon\-(\d+).xbm",f)
    prefix = m.group(1)
    charwidth = m.group(2)
    if prefix not in fontconfig:
      fontconfig[prefix] = {}

    with open(f,"r") as fd:
      for lin in fd.readlines():
        m = re.match(".+width (\d+)", lin)
        if m:
          colon_width = m.group(1)
          break
    fontconfig[prefix][charwidth] = colon_width
  with open("images/digits.ini","w") as fil:
    fontconfig.write(fil)
  logging.info("done")
else:
  fontconfig.read("images/digits.ini")



# http request setup

def check_time():
  global secs
  global timeron

  logging.debug("calling check_time()")
  if not(HTTPREQ):
    secs = 120
    return 
  with Session() as session:
    with session.get("http://localhost/time") as r:
      http_code = r.status_code
      if http_code == 200:
        logging.debug("content = %s" % str(r.content))
        js = json.loads(r.content)
        if timeron == False and js["status"] == 'ON':
          timeron = True
        if timeron == True and js["status"] == 'OFF':
          timeron = False
        secs = js["secs"]

#
# the big canvas redraw!
#

charwidth=-1
screenwidth=-1

def charw():
  logging.debug("calling charw()")
  global frame,screenwidth,charwidth
  if screenwidth == frame.winfo_width():
    logging.debug("returning cached value")
    return charwidth
  else:
    screenwidth = frame.winfo_width()
    charwidth = -1
    for k in fontconfig[PREFIX].keys():
      if int(k) > charwidth and screenwidth > 3 * int(k) + int(fontconfig[PREFIX][k]):
        charwidth = int(k)
    logging.debug("new value = %d" % charwidth)
    return charwidth

def redraw_xbm():
  global canvas, secs, timeron, frame
  logging.debug("calling redraw_xbm()")
  blink = secs < -15 and int(time.time()) % 2
  digit1 = 0
  digit2 = 0
  digit3 = 0
  cw = 0
  if secs > 0:
    digit1 = int(secs / 60)
    digit2 = int((secs % 60) / 10)
    digit3 = secs % 10
  canvas.delete('all')
  if frame.winfo_width() <= 1:
    return

  bkgcol = ''
  txtcol = 'black'
  if not(timeron):
    #canvas.configure(bg=OFFBKGCOL)
    bkgcol=OFFBKGCOL
  else:
    for x in BKGCOL.keys():
      if secs <= x:
        #canvas.configure(bg=BKGCOL[x])
        bkgcol=BKGCOL[x]
        break

  canvas.configure(bg=(txtcol if blink else bkgcol))
  cw = charw()
  if cw <= 0:
    return
  colonw = int(fontconfig[PREFIX][str(cw)])
  sw = 3 * cw + colonw
  canvas.create_bitmap(frame.winfo_width() / 2 - sw / 2, frame.winfo_height() / 2, bitmap="@images/%s-%d-%d.xbm" % (PREFIX,digit1,cw),anchor=W,foreground=(bkgcol if blink else txtcol))
  canvas.create_bitmap(frame.winfo_width() / 2 - sw / 2 + cw, frame.winfo_height() / 2, bitmap="@images/%s-colon-%d.xbm" % (PREFIX,cw),anchor=W,foreground=(bkgcol if blink else txtcol))
  canvas.create_bitmap(frame.winfo_width() / 2 - sw / 2 + cw + colonw, frame.winfo_height() / 2, bitmap="@images/%s-%d-%d.xbm" % (PREFIX,digit2,cw),anchor=W,foreground=(bkgcol if blink else txtcol))
  canvas.create_bitmap(frame.winfo_width() / 2 - sw / 2 + 2 * cw + colonw, frame.winfo_height() / 2, bitmap="@images/%s-%d-%d.xbm" % (PREFIX,digit3,cw),anchor=W,foreground=(bkgcol if blink else txtcol))
  

# resize does the job of checking the current window size and updating vars
def resize(event=None):
  global frame
  global canvas
  logging.debug("calling resize()")

  # assuming portrait aspect here
  canvas.configure(width=frame.winfo_width(),height=frame.winfo_height())
  redraw_xbm()

# the main interface to update time call and redraw

def update():
  logging.debug("calling update()")
  check_time()
  redraw_xbm()
  root.after(100,update)


# main app window creation

root = Tk()
root.title("20x2 Chicago timer")

# create the frame which will hold the canvas
frame = Frame(root, bg='black')
frame.pack(fill=BOTH,expand=1)

# the canvas obj
canvas = Canvas(frame,bg='black',highlightthickness=0)
canvas.pack(expand=YES,fill=BOTH)

root.bind('<Configure>',resize)
root.after(20,update)
root.attributes('-fullscreen',True)
resize()

# turn off pointer
root.config(cursor="none")

# force focus to new window
root.after(1, lambda: root.focus_force())

# loop
root.mainloop()

