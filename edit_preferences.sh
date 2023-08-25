#!/usr/bin/env bash
#-------------------------------------------------------------------------
# Companion script to Plex_Server_Sync.sh
#
# https://github.com/tigattack/Plex_Server_Sync
#--------------------------------------------------------------------------

# Assign Excluded_preferences_keys string array
Excluded_preferences_keys=(
    # Default exclude keys
    "AnonymousMachineIdentifier"
    "CertificateUUID"
    "FriendlyName"
    "LastAutomaticMappedPort"
    "MachineIdentifier"
    "ManualPortMappingPort"
    "PlexOnlineToken"
    "ProcessedMachineIdentifier"
    # Custom exclude keys
    "PubSubServerPing"
    "allowMediaDeletion"
    "DatabaseCacheSize"
    "TranscoderQuality"
    "LanNetworksBandwidth"
    "FSEventLibraryPartialScanEnabled"
    "FSEventLibraryUpdatesEnabled"
    "ScheduledLibraryUpdatesEnabled"
    "GenerateBIFBehavior"
    "GenerateChapterThumbBehavior"
    "GenerateCreditsMarkerBehavior"
    "GenerateIntroMarkerBehavior"
    "LoudnessAnalysisBehavior"
    "MusicAnalysisBehavior"
    "ButlerTaskOptimizeDatabase"
    "ButlerTaskUpgradeMediaAnalysis"
    "ButlerTaskRefreshPeriodicMetadata"
    "ButlerTaskDeepMediaAnalysis"
    "ButlerTaskRefreshLocalMedia"
    "ButlerTaskBackupDatabase"
    "TranscoderCanOnlyRemuxVideo"
    "TranscodeCountLimit"
    "TranscoderToneMapping"
    "TranscoderQuality"
)

cd "$(dirname "$0")" || {
    echo "cd $(dirname "$0") failed!"
    exit 1
}
#echo $PWD  # debug

if [[ ! -f Preferences.bak ]]; then
    echo "Preferences.bak not found! Aborting."
    exit 1
elif [[ ! -f Preferences.xml ]]; then
    echo "Preferences.xml not found! Aborting."
    exit 1
fi

# Padding var for formatting
padding="                                  "

# Get length of Excluded_preferences_keys
Len=${#Excluded_preferences_keys[@]}

# Get backup Preferences.bak file's ID values
echo -e "\nPreferences.bak"
declare -A Pref_bak
Num="0"
while [[ $Num -lt "$Len" ]]; do
    Pref_bak[$Num]=$(grep -oP "(?<=\b${Excluded_preferences_keys[$Num]}=\").*?(?=(\" |\"/>))" "Preferences.bak")
    #echo "${Excluded_preferences_keys[$Num]} = ${Pref_bak[$Num]}"
    echo "${Excluded_preferences_keys[$Num]}${padding:${#Excluded_preferences_keys[$Num]}} = ${Pref_bak[$Num]}"
    Num=$((Num + 1))
done

# Get synced Preferences.xml file's ID values (so we can replace them)
echo -e "\nPreferences.xml"
declare -A Pref_new
Num="0"
while [[ $Num -lt "$Len" ]]; do
    Pref_new[$Num]=$(grep -oP "(?<=\b${Excluded_preferences_keys[$Num]}=\").*?(?=(\" |\"/>))" "Preferences.xml")
    #echo "${Excluded_preferences_keys[$Num]} = ${Pref_new[$Num]}"
    echo "${Excluded_preferences_keys[$Num]}${padding:${#Excluded_preferences_keys[$Num]}} = ${Pref_new[$Num]}"
    Num=$((Num + 1))
done
echo

# Change synced Preferences.xml ID values to backed up ID values
changed=0
Num="0"
while [[ $Num -lt "$Len" ]]; do
    if [[ ${Pref_new[$Num]} ]] && [[ ${Pref_bak[$Num]} ]]; then
        if [[ ${Pref_new[$Num]} != "${Pref_bak[$Num]}" ]]; then
            echo "Updating ${Excluded_preferences_keys[$Num]}"
            sed -i "s~ ${Excluded_preferences_keys[$Num]}=\"${Pref_new[$Num]}~ ${Excluded_preferences_keys[$Num]}=\"${Pref_bak[$Num]}~g" "Preferences.xml"
            changed=$((changed + 1))
        fi
    fi
    Num=$((Num + 1))
done

# VaapiDriver in Preferences.bak
VaapiDriver=$(grep -oP '(?<=\bVaapiDriver=").*?(?=(" |"/>))' "Preferences.bak")
echo -e "Back_VaapiDriver                = $VaapiDriver\n"

# VaapiDriver in Preferences.xml
Main_VaapiDriver=$(grep -oP '(?<=\bVaapiDriver=").*?(?=(" |"/>))' "Preferences.xml")
echo -e "Main_VaapiDriver                = $Main_VaapiDriver\n"

# VaapiDriver
if [[ $Main_VaapiDriver ]] && [[ $VaapiDriver ]]; then
    if [[ $Main_VaapiDriver != "$VaapiDriver" ]]; then
        #echo -e "Updating VaapiDriver\n"
        echo "Updating VaapiDriver"
        sed -i "s/ VaapiDriver=\"${Main_VaapiDriver}/ VaapiDriver=\"${VaapiDriver}/g" "Preferences.xml"
        changed=$((changed + 1))
    else
        #echo -e "Same VaapiDriver already\n"
        echo "Same VaapiDriver already"
    fi
elif [[ $VaapiDriver ]]; then
    # Insert VaapiDriver="i965" or VaapiDriver="iHD" at the end, before />
    #echo -e "Adding VaapiDriver\n"
    echo "Adding VaapiDriver"
    sed -i "s/\/>/ VaapiDriver=\"${VaapiDriver}\"\/>/g" "Preferences.xml"
    changed=$((changed + 1))
elif [[ $Main_VaapiDriver ]]; then
    # Delete VaapiDriver="i965" or VaapiDriver="iHD"
    #echo -e "Deleting VaapiDriver\n"
    echo "Deleting VaapiDriver"
    sed -i "s/ VaapiDriver=\"${Main_VaapiDriver}\"//g" "Preferences.xml"
    changed=$((changed + 1))
fi

if [[ $changed -eq "1" ]]; then
    echo -e "\n$changed change made in Preferences.xml"
elif [[ $changed -gt "0" ]]; then
    echo -e "\n$changed changes made in Preferences.xml"
else
    echo -e "\nNo changes needed in Preferences.xml"
fi

exit
