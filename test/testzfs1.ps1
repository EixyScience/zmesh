zfs.exe get driveletter zmtest
zfs.exe set driveletter=off zmtest
zpool.exe export zmtest
zpool.exe import zmtest
zfs.exe mount
zfs.exe list -o name,mountpoint,driveletter