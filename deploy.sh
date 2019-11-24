#!/bin/sh
echo "-- Compiling HTML"
hugo -D
echo "-- rsync'ing to the moon..."
if [ `uname -s` == "OpenBSD" ]; then
  RSYNC_CMD=openrsync
else
  RSYNC_CMD=rsync
fi
${RSYNC_CMD} -avz -e "ssh -i ~/.ssh/id_moon" ./public/ moon:/var/www/sites/www.sisu.io/
echo "-- DONE!"
