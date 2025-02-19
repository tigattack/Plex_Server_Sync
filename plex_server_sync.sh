#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Script to sync Plex server database & metadata to backup Plex server.
#
# It also syncs your settings, though you can disable this by adding the
# following to the included plex_rsync_exclude.txt
# Preferences.xml
#
# Requirements:
#   The script MUST be run on the device where the main Plex server is.
#   The following files must be in the same folder as Plex_Server_Sync.sh
#     1. plex_server_sync.config
#     2. plex_rsync_exclude.txt
#     3. edit_preferences.sh
#
# If you want to schedule this script to run as a user:
#  1. You need SSH keys setup so rsync can connect without passwords.
#  2. You also need your user to be able to sudo without a password prompt.
#
# https://github.com/tigattack/Plex_Server_Sync
#------------------------------------------------------------------------------

# Check if script is running in GNU bash and not BusyBox ash
Shell=$(/proc/self/exe --version 2>/dev/null | grep "GNU bash" | cut -d "," -f1)
if [ "$Shell" != "GNU bash" ]; then
    echo -e "\nYou need to install bash to be able to run this script."
    echo -e "\nIf running this script on an ASUSTOR:"
    echo "1. Install Entware from App Central"
    echo "2. Run the following commands in a shell:"
    echo "opkg update && opkg upgrade"
    echo -e "opkg install bash\n"
    exit 1
fi

SCRIPTPATH="$(
    cd -- "$(dirname "$0")" >/dev/null 2>&1
    pwd -P
)"

# Read variables from plex_server_sync.config
if [[ -f "$SCRIPTPATH/plex_server_sync.config" ]]; then
    source "$SCRIPTPATH/plex_server_sync.config"
else
    echo "plex_server_sync.config file missing!"
    exit 1
fi

#-----------------------------------------------------
# Set date and time variables

# Timer variable to log time taken to sync PMS
start="${SECONDS}"

# Get Start Time and Date
Started=$(date)

#-----------------------------------------------------
# Set log file name

if [[ ! -d $LogPath ]]; then
    LogPath=$SCRIPTPATH
fi
Log="$LogPath/$(date '+%Y%m%d')_Plex_Server_Sync.log"
if [[ -f $Log ]]; then
    # Include hh-mm if log file already exists (already run today)
    Log="$LogPath/$(date '+%Y%m%d-%H%M')_Plex_Server_Sync.log"
fi
ErrLog="${Log%.*}_ERRORS.log"

# Log header
CYAN='\e[0;36m'
WHITE='\e[0;37m'
echo -e "${CYAN}--- Plex Server Sync ---${WHITE}" # shell only
echo -e "--- Plex Server Sync ---\n" 1>>"$Log"    # log only
echo -e "Syncing $src_IP to $dst_IP\n" |& tee -a "$Log"

#-----------------------------------------------------
# Initial checks

# Convert hostnames to lower case
src_IP=${src_IP,,}
dst_IP=${dst_IP,,}

if [[ -z $dst_SshPort ]]; then dst_SshPort=22; fi

if [[ ! $dst_SshPort =~ ^[0-9]+$ ]]; then
    echo "Aborting! Destination SSH Port is not numeric: $dst_SshPort" |& tee -a "$Log"
    exit 1
fi

Exclude_File="$SCRIPTPATH/plex_rsync_exclude.txt"
if [[ ! -f $Exclude_File ]]; then
    echo -e "Aborting! Exclude_File not found: \n$Exclude_File" |& tee -a "$Log"
    exit 1
fi

edit_preferences="$SCRIPTPATH/edit_preferences.sh"
if [[ ! -f $edit_preferences ]]; then
    echo -e "Aborting! edit_preferences.sh not found: \n$edit_preferences" |& tee -a "$Log"
    exit 1
fi

# Check script is running on the source device
host=$(hostname)                                         # for comparability
ip=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q') # for comparability
if [[ $src_IP != "${host,,}" ]] && [[ $src_IP != "$ip" ]]; then
    echo "Aborting! Script is not running on source device: $src_IP" |& tee -a "$Log"
    exit 1
fi

echo "Source:      $src_Directory" |& tee -a "$Log"
echo "Destination: $dst_Directory" |& tee -a "$Log"

if [[ ${Delete,,} != "yes" ]] && [[ ${Delete,,} != "no" ]]; then
    echo -e "\nDelete extra files on destination? [y/n]:" |& tee -a "$Log"
    read -r -t 10 answer
    if [[ ${answer,,} == y ]]; then
        Delete=yes
        echo yes 1>>"$Log"
    else
        echo no 1>>"$Log"
    fi
    answer=
fi

if [[ ${DryRun,,} != "yes" ]] && [[ ${DryRun,,} != "no" ]]; then
    echo -e "\nDo a dry run test? [y/n]:" |& tee -a "$Log"
    read -r -t 10 answer
    if [[ ${answer,,} == y ]]; then
        DryRun=yes
        echo yes 1>>"$Log"
    else
        echo no 1>>"$Log"
    fi
    answer=
fi

#-----------------------------------------------------
# Check host and destination are not the same

# This function is also used by PlexVersion function
function Host2IP() {
    if [[ $2 == "remote" ]]; then
        # Get remote IP from hostname
        ip=$(ssh "${dst_User}@${1,,}" -p "$dst_SshPort" -i "$ssh_Key_File" \
            "ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q'")
    else
        # Get local IP from hostname
        ip=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
    fi
    echo "$ip"
}

# Check the source isn't also the target
if [[ $src_IP == "$dst_IP" ]]; then
    echo -e "\nSource and Target are the same!" |& tee -a "$Log"
    echo "Source: $src_IP" |& tee -a "$Log"
    echo "Target: $dst_IP" |& tee -a "$Log"
    exit 1
elif [[ $(Host2IP "$src_IP") == $(Host2IP "$dst_IP" remote) ]]; then
    echo -e "\nSource and Target are the same!"
    echo "Source: $src_IP"
    echo "Target: $dst_IP"
    exit 1
fi

#-----------------------------------------------------
# Get Plex version BEFORE we stop both Plex servers

# we can get the Plex version from Plex binary but location is OS dependant
# so we'll use the independent method (but it requires Plex to be running)

function PlexVersion() {
    if [[ $2 == "remote" ]]; then
        ip=$(Host2IP "$1" remote)
    else
        ip=$(Host2IP "$1")
    fi
    if [[ $ip ]]; then
        # Get Plex version from IP address
        Response=$(curl -s "http://${ip}:32400/identity")
        ver=$(printf %s "$Response" | grep '" version=' | awk -F= '$1=="version"\
            {print $2}' RS=' ' | cut -d'"' -f2 | cut -d\- -f1)
        echo "$ver"
    fi
    return
}

src_Version=$(PlexVersion "$src_IP")
echo -e "\nSource Plex version:      $src_Version" |& tee -a "$Log"

dst_Version=$(PlexVersion "$dst_IP" remote)
echo -e "Destination Plex version: $dst_Version\n" |& tee -a "$Log"

if [[ ! $src_Version ]] || [[ ! $dst_Version ]]; then
    echo "WARN: Unable to get one or both Plex versions." |& tee -a "$Log"
    echo "One or both servers may be stopped already." |& tee -a "$Log"
    echo "Are both Plex versions the same? [y/n]" |& tee -a "$Log"
    read -r answer
    if [[ ${answer,,} != y ]]; then
        echo no 1>>"$Log"
        exit 1
    else
        echo yes 1>>"$Log"
    fi
fi

# Check both versions are the same
if [[ $src_Version != "$dst_Version" ]]; then
    if [[ $answer != "y" ]]; then
        echo "Plex versions are different. Aborting." |& tee -a "$Log"
        echo -e "Source:      $src_Version \nDestination: $dst_Version" |& tee -a "$Log"
        exit 1
    fi
fi

#-----------------------------------------------------
# Plex Stop Start function

function PlexControl() {
    if [[ $1 == "start" ]] || [[ $1 == "stop" ]]; then
        if [[ $2 == "local" ]]; then
            # stop or start local server
            sudo systemctl "$1" plexmediaserver
        elif [[ $2 == "remote" ]]; then
            # stop or start remote server
            ssh "${dst_User}@${dst_IP}" -p "$dst_SshPort" -i "$ssh_Key_File" "sudo systemctl $1 plexmediaserver"
        else
            echo "Invalid parameter #2: $2" |& tee -a "$Log"
            exit 1
        fi
        if [[ $1 == "stop" ]]; then
            sleep 5 # Give sockets a moment to close
        fi
    else
        echo "Invalid parameter #1: $1" |& tee -a "$Log"
        exit 1
    fi
    return
}

#-----------------------------------------------------
# Stop both Plex servers

echo "Stopping Plex on $src_IP" |& tee -a "$Log"
PlexControl stop local |& tee -a "$Log"
echo -e "\nStopping Plex on $dst_IP" |& tee -a "$Log"
PlexControl stop remote |& tee -a "$Log"
echo >>"$Log"

#-----------------------------------------------------
# Check both servers have stopped

# not the best way to get Plex status but other ways are OS dependant

abort=
if [[ $(PlexVersion "$src_IP") ]]; then
    echo "Source Plex $src_IP is still running!" |& tee -a "$Log"
    abort=1
fi
if [[ $(PlexVersion "$dst_IP" remote) ]]; then
    echo "Destination Plex $dst_IP is still running!" |& tee -a "$Log"
    abort=1
fi
if [[ $abort ]]; then
    echo "Aborting!" |& tee -a "$Log"
    exit 1
fi

#-----------------------------------------------------
# Backup destination Preferences.xml

# Backup Preferences.xml to Preferences.bak
echo "Backing up destination Preferences.xml to Preferences.bak" |& tee -a "$Log"
ssh "${dst_User}@${dst_IP}" -p "$dst_SshPort" -i "$ssh_Key_File" \
    "sudo cp -pu '${dst_Directory}/Preferences.xml' '${dst_Directory}/Preferences.bak'" |& tee -a "$Log"

#-----------------------------------------------------
# Sync source to destination with rsync

cd / || {
    echo "cd / failed!" |& tee -a "$Log"
    exit 1
}
echo ""

# ------ rsync flags used ------
# --rsh destination shell to use
# -r recursive
# -l copy symlinks as symlinks
# -h human readable
# -p preserver permissions <-- FAILED to set permissions. Operation not permitted. Need to test more.
# -t preserve modification times
# -O don't keep directory's mtime (with -t)
# --progress              show progress during transfer
# --stats give some file-transfer stats
#
# ------ optional rsync flags ------
# --delete        delete extraneous files from destination dirs
# -n, --dry-run   perform a trial run with no changes made

# Unset any existing arguments
while [[ $1 ]]; do shift; done

if [[ ${DryRun,,} == yes ]]; then
    # Set --dry-run flag for rsync
    set -- "$@" "--dry-run"
    echo Running an rsync dry-run test |& tee -a "$Log"
fi
if [[ ${Delete,,} == yes ]]; then
    # Set --delete flag for rsync
    set -- "$@" "--delete"
    echo Running rsync with delete flag |& tee -a "$Log"
fi

# --delete doesn't delete if you have * wildcard after source directory path
rsync --rsh="ssh -p$dst_SshPort -i \"$ssh_Key_File\"" --rsync-path="sudo rsync" \
    -rlhtO "$@" --progress --stats --exclude-from="$Exclude_File" \
    "$src_Directory/" "$dst_User@$dst_IP":"${dst_Directory// /\\ }/" |& tee -a "$Log"

#-----------------------------------------------------
# Restore unique IDs to destination's Preferences.xml

echo -e "\nCopying edit_preferences.sh to destination" |& tee -a "$Log"

# Ensure executable bit is set on edit_preferences.sh
chmod +x "$SCRIPTPATH/edit_preferences.sh"

rsync --rsh="ssh -p$dst_SshPort -i \"$ssh_Key_File\"" --rsync-path="sudo rsync" -Eh --progress \
    "$SCRIPTPATH/edit_preferences.sh" "$dst_User@$dst_IP":"${dst_Directory// /\\ }/"

echo -e "\nRunning $dst_Directory/edit_preferences.sh" |& tee -a "$Log"
ssh "${dst_User}@${dst_IP}" -p "$dst_SshPort" -i "$ssh_Key_File" "sudo '${dst_Directory}/edit_preferences.sh'" |& tee -a "$Log"


#-----------------------------------------------------
# Ensure destination directory is owned by Plex

echo -e "\nSetting permissions on destination directory" |& tee -a "$Log"
ssh "${dst_User}@${dst_IP}" -p "$dst_SshPort" -i "$ssh_Key_File" "sudo chown -R plex. '${dst_Directory}'" |& tee -a "$Log"

#-----------------------------------------------------
# Start both Plex servers

echo -e "\nStarting Plex on $src_IP" |& tee -a "$Log"
PlexControl start local |& tee -a "$Log"
echo -e "\nStarting Plex on $dst_IP" |& tee -a "$Log"
PlexControl start remote |& tee -a "$Log"

#-----------------------------------------------------
# Check if there errors from rsync or cp

if [[ -f $Log ]]; then
    tmp=$(awk '/^(rsync|cp|\*\*\*|IO error).*/' "$Log")
    if [[ -n $tmp ]]; then
        echo "$tmp" >>"$ErrLog"
    fi
fi
if [[ -f $ErrLog ]]; then
    echo -e "\n${CYAN}Some errors occurred!${WHITE} See:" # shell only
    echo -e "\nSome errors occurred! See:" >>"$Log"       # log only
    echo "$ErrLog" |& tee -a "$Log"
fi

#--------------------------------------------------------------------------
# Append the time taken to stdout

# End Time and Date
Finished=$(date)

# bash timer variable to log time taken
end="${SECONDS}"

# Elapsed time in seconds
Runtime=$((end - start))

# Append start and end date/time and runtime
echo -e "\nBackup Started: " "${Started}" |& tee -a "$Log"
echo "Plex Sync Finished:" "${Finished}" |& tee -a "$Log"
# Append days, hours, minutes and seconds from $Runtime
printf "Plex Sync Duration: " |& tee -a "$Log"
printf '%dd:%02dh:%02dm:%02ds\n' \
    $((Runtime / 86400)) $((Runtime % 86400 / 3600)) $((Runtime % 3600 / 60)) $((Runtime % 60)) |& tee -a "$Log"
echo "" |& tee -a "$Log"

exit
