zfs.exe set mountpoint="C:\zpool\zmtest" zmtest
zpool.exe export zmtest
zpool.exe import zmtest
zfs.exe mount
zfs.exe list -o name,mountpoint