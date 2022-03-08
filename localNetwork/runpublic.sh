# Grab the IP of the NIC inside of our machine so we can 'sed' it into the
# config files
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    export IP=$(netstat -nr | grep default | grep -v tun | awk '{print $2}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS/iOS/watchOS/tvOS/iPadOS/some Darwin distros
    export IP=$(ipconfig getifaddr $(netstat -nr | grep default | head -1 | awk '{print $4}'))
else
    # Unknown.
    echo I don\'t know how to get an IP from your OS!
    exit
fi

# Backup the configs to a folder labelled after the epoch, so an alphabetical
# sort will sort the oldest to newest. Your oldest backup is probably the
# original files, but I would suggest trying "git reset --hard" instead if you
# just want to revert your configs.
mkdir -p configbackups
cp -r configurations configbackups/$(date +%s)

# Replace local IPs with the IP our NIC has in all config files
sed -i '.bak' "s/127\.0\.0\.1/$IP/g" configurations/*
sed -i '.bak' "s/0\.0\.0\.0/$IP/g" configurations/*
# Since we back the files up into configbackups, this is only clutter after
# the sed commands finish. We can clean it up.
rm configurations/*.bak

# Run the localenvironment
echo "Preparing to run on $IP ..."
./run.sh
