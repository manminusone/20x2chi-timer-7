#!/bin/bash
#
# generate-digits -- a script to use ImageMagick to automatically create XBM images used 
# in the Python time display program.
#
# Since the issue with displaying digits appears to be width instead of height, this
# script will create a bunch of various sizes of digits and the clock script will 
# measure the screen width to figure out which one to use. So the number in the 
# file name refers to the width of the character, not height.
#
# -f <fontfile> -- font to use (should be monospace; expecting the digits to be the same width)
# -d <directory> -- location for output (defaults to current dir)
# -p <prefix> -- prefix to use for the digit file names
#
# Reqired programs:
# 
# - perl (should be installed)
# - ImageMagick (you may need to manually install)
#

prefix="lcd"
fontname=""
outdir="."

# make_image creates the file for the indicated digit. Arguments:
# - the text to make (should be one char)
# - the desired width
# - the char to be used in the file name (provided so the filename for the ":" char can be set properly)
make_image () {

    # colons will not be the same width as the digits so you need to use
    # whatever the digit height was determined to be to resize the image.
    # So make sure you always make_image a digit before a colon.

    if [[ "$1" == ":" ]]
    then
        resizeString="x$digitheight"
        echo "Colon detected. resize string = $resizeString"
    else
        resizeString="$2"
    fi
    imgsize=$(convert -debug annotate xc: -font "$fontname" -pointsize "1000" -annotate 0 "$1" null: 2>&1 | grep Metrics: | perl -e '$_=<STDIN>;($h)=/height: (\d+)/;($w)=/width: (\d+)/;print "${w}x${h}\n"' )
    convert -size "$imgsize" canvas:white -fill black -gravity center -font "$fontname" -pointsize "1000" -annotate 0 "$1" -resize "$resizeString" "$outdir/$prefix-$3-$width.xbm"

    # keep track of the digit height, to be used for colon char
    if [[ "$1" != ":" ]]
    then
        digitheight=$(grep height "$outdir/$prefix-$3-$width.xbm" | cut -f 3 -d " ")
    fi
}

for i in convert perl
do
    if [[ $(which $i) != *"$i"* ]]; then
        echo "I don't see $i in the PATH. Check to confirm that required programs are installed"
        exit 0
    fi 
done

while getopts f:d:p: item 
do
    case $item in 
        f) if [[ ! -f "${OPTARG}" ]]
           then
            echo "I don't see the font file"
            exit 1
           fi
           fontname="${OPTARG}";;
        d) if [[ ! -d "${OPTARG}" ]]
           then
              echo "Output directory has to exist"
              exit 1
            fi
            outdir="${OPTARG}";;
        p) prefix="${OPTARG}";;
        *) ;;
    esac
done

if [[ "$fontname" == "" ]]
then
    echo "You need to provide a font file on the command line."
    exit 1
fi

# These are probably more sizes than are necessary, but it's good to be prepared for any case
for width in 200 300 400 500 600 700
do
    echo Creating charset with $width pixel width
    for dig in 0 1 2 3 4 5 6 7 8 9
    do
        make_image $dig $width $dig
    done
    make_image ':' $width 'colon'
done