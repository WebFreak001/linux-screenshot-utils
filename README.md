# linux-screenshot-utils

Better screenshot selector to use in shell scripts.

## Installation:

Install dub, gtk dev, x11 dev
Optionally also install xclip, paplay or other utilities you might want to use in your workflows.

## Selector utility

run `dub build --root=capture` to create the screenshot capture utility.

To create a minimal size utility run `dub build --root=capture --compiler=ldc2 --build=release && strip capture/capture`

You can use the selector utility with the "fullscreen" argument to make a fullscreen screenshot like xwd with direct conversion to a file format. For further conversion the BMP format is recommended as it is the fastest to encode and decode.

You can also use "region" or "objects" to have a selection GUI open. It will freeze what is currently on the screen when the command is run so screenshotting is easy.

You can also make links to the selector utility or rename it to force a specific selection mode. If the executable name ends with `-region`, `-objects`, `-fullscreen` or `-window`, their respective modes will be used as argument automatically.

To make screenshots:
```bash
#!/bin/bash
capture-objects png > /tmp/screenshot.png || exit 1
file=`image-history push /tmp/screenshot.png`
thumbnail="/tmp/screenshot-thumbnail-$$.bmp"
# gimp $file
url=`image-upload $file`
echo -n $url | xclip -sel clip
convert $file -resize "400x150>" $thumbnail
# kdialog --title "Successfully uploaded" --passivepopup "<img src='file://$thumbnail'>"
notify-send "Screenshot Uploaded" "<img src=\"file://$thumbnail\" alt=\"$url\"/>"
```
