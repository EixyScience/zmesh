# 親を先に作る（または -p で一発）
zfs.exe create -p zmtest/scalefs/default/default/default

# その後に cell dataset
zfs.exe create zmtest/scalefs/default/default/default/democell-28e671

# mountpoint を main に向ける
zfs.exe set mountpoint="C:\scalefsroot\democell.28e671\main" zmtest/scalefs/default/default/default/democell-28e671