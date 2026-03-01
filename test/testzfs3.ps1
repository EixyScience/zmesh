zfs.exe set driveletter=off zmtest/scalefs
zfs.exe create -p zmtest/scalefs
zfs.exe create zmtest/scalefs/democell-28e671
zfs.exe set driveletter=off zmtest/scalefs/democell-28e671
zfs.exe set mountpoint="C:\scalefsroot\democell.28e671\main" zmtest/scalefs/democell-28e671
zfs.exe mount zmtest/scalefs/democell-28e671
zfs.exe mount