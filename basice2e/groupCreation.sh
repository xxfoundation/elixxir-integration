#!/bin/bash

ouputFile=groupMembers


if [ $# -eq 0 ]; then
    echo "No arguments provided. Please provide the path to client logs.
    These client logs should be for clients you wish to create a group with via
    the client API/CLI. NOTE: Exclude the path for the client that will create
     the group."
    exit 1
fi


# This
touch $ouputFile
for file in "$@"
do
    if [ ! -f "$file" ]
    then
        echo "File $file could not be found, skipping"
        continue
    fi

    TMPID=$(cat $file | grep -a "User\:" | awk -F' ' '{print $5}')
    echo "User ID for $file: $TMPID"
    echo "b64:TMPID" >> $ouputFile

done

echo "Group IDs have been outputted to file \"$ouputFile\".
 Please pass this file in to the --create flag when creating a group
 via client CLI."
