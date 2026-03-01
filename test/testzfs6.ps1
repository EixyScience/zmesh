zfs.exe set mountpoint=/scalefs/democell-28e671 zmtest/scalefs/democell-28e671
zfs.exe mount zmtest/scalefs/democell-28e671
zfs.exe list -o name,mountpoint,driveletter zmtest/scalefs/democell-28e671