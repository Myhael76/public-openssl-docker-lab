#!/bin/sh

# Absolute path to this script, e.g. /home/user/bin/foo.sh
THIS_SCRIPT_START=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
THIS_SCRIPT_HOME=$(dirname "$THIS_SCRIPT_START")


### "Import command library"
. ${LAB_BIN_FOLDER}/commands.sh

manageAllSubjects

if [ ${LAB_DEBUG} -eq 1 ]; then
    echo "stopping for debug"
    tail -f /dev/null
fi