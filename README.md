# Plex Server Sync
Sync main Plex server database &amp; metadata to a backup Plex server

<p align="center"><img src="plex_server_sync_logo.png"></p>

This fork is modified for my own use cases.

Summary of changes:
- Use sudo everywhere - My Plex appdata directory is unreadable for users other than plex.
- Use rsync instead of scp - Same reason as above.
- Remove DSM/Asustor support - Eliminate complexity from features I don't need.
- Some bug fixes and code cleanup.

### Description

Plex Server Sync is a bash script to sync one Plex Media Server to another Plex Media Server, **including played status, play progress, posters, metadata, ratings and settings**. The only things not synced are settings specific to each Plex Media Server (like server ID, friendly name, public port etc), and files and folders listed in the plex_rsync_exclude.txt file.

This script was written for people who:

* Have setup a clean installation of Plex Media Server on a different device and want to migrate their Plex settings, meta data, database, played status and played progress to the new device.
* Have a main Plex server and a backup Plex server and want to keep the backup server in sync with the main server. 
* Have a Plex server at home and a Plex server at their holiday house and want to sync to their holiday house Plex server before leaving home, and then sync back to their home Plex server before leaving the holiday house to return home.

The script needs to run on the source plex server machine.

Tested on Debian 11.

#### What the script does

* Gets the Plex version from both Plex servers.
* Stops both the source and destination Plex servers.
* Backs up the destination Plex server's Preferences.xml file.
* Copies all newer data files from the source Plex server to the destination Plex server.
  * Files listed in the exclude file will not be copied.
* Optionally deletes any extra files in the destination Plex server's data folder.
  * Files listed in the exclude file will not be deleted.
* Restores the destination Plex server's machine specific settings in Preferences.xml.
* Starts both Plex servers.

Everything is saved to a log file, and any errors are also saved to an error log file.

#### What the script does NOT do

It does **not** do a 2-way sync. It only syncs one Plex server to another Plex server.

### Requirements

1. **The script needs to run on the source Plex Media Server machine.**

2. **The following files must be in the same folder as plex_server_sync.sh**

   ```YAML
   edit_preferences.sh
   plex_rsync_exclude.txt
   plex_server_sync.config
   ```

3. **Both Plex servers must be running the same Plex Media Server version**

4. **Both Plex servers must have the same library path**

   If the source Plex server accesses it's media libraries at "/volume1/videos" and "/volume1/music" then the destination server also needs to access it's media libraries at "/volume1/videos" and "/volume1/music"

5. **SSH Keys and sudoers**

   If you want to schedule the script to run unattended, as a scheduled cron job, the users need to have passwordless sudo enabled and SSH keys setup so that the SSH and rsync commands can access the remote server without you entering the user's password. 

### Settings

You need to set the source and destination settings in the [plex_server_sync.config](plex_server_sync.config) file. There are also a few optional settings in the plex_server_sync.config file.

**For example:**

```YAML
src_IP=192.168.0.70
src_Directory="/volume1/PlexMediaServer/AppData/Plex Media Server"
src_User=Bob

dst_IP=192.168.0.60
dst_Directory="/volume1/Plex/Library/Application Support/Plex Media Server"
dst_User=Bob
dst_SshPort=22

Delete=yes
DryRun=no
LogPath=~/plex_server_sync_logs
```

### Default contents of plex_rsync_exclude.txt

Any files or folders listed in plex_rsync_exclude.txt will **not** be synced. The first 4 files listed must never be synced from one server to another. The folders listed are optional.

**Contents of plex_rsync_exclude.txt**

```YAMLedit_preferences.sh
Preferences.bak
.LocalAdminToken
plexmediaserver.pid
Cache
Codecs
Crash Reports
Diagnostics
Drivers
Logs
Updates
```
