The XBM files in this directory were generated from two different font files: Jan Bobrowski's [7-segment font,](http://torinak.com/font/7-segment) and Keshikan's very impressive [DSEG collection.](https://www.keshikan.net/fonts-e.html) You may generate your own digit images using the generate-digits.sh script located in the install-scripts/ directory. See the script for details.

The format of the image name is "PREFIX-CHAR-WIDTH.xbm".

* PREFIX is a common prefix that indicates the files belong to the same font.
* CHAR is the char being displayed in the image. Valid values are 0 through 9, and 'colon' for the colon character used in the time display.
* WIDTH is the width of the image. When the script starts it checks the current screen resolution (or rather the size of the Tk canvas that has been created) and looks for the largest set of images that can be displayed. This appears to work pretty well on most screen resolutions that I have tested.

Not all of the width values are used by the script; I just generated them in case I need to run the timer on some weird screen resolution in the future.