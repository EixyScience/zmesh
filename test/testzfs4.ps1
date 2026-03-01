# 0) 事前：作業ディレクトリ（必要なら）
New-Item -ItemType Directory -Force C:\scalefsroot | Out-Null
New-Item -ItemType Directory -Force C:\zfs-mp      | Out-Null

# 1) pool ルートは “見せない”
zfs.exe set mountpoint=none zmtest
zfs.exe set driveletter=off zmtest

# 2) 親 dataset を作る（-p で親も作る）
zfs.exe create -p zmtest/scalefs

# 3) 親も driveletter=off（以降の子にも明示的に off 推奨）
zfs.exe set driveletter=off zmtest/scalefs

# 4) 例：democell-28e671 を作る
$ds = "zmtest/scalefs/democell-28e671"
zfs.exe create $ds

# 5) dataset も driveletter=off
zfs.exe set driveletter=off $ds

# 6) mountpoint は Windows 絶対パス（重要：スラッシュ区切り）
$mp = "C:/scalefsroot/democell.28e671/main"
New-Item -ItemType Directory -Force "C:\scalefsroot\democell.28e671\main" | Out-Null
zfs.exe set mountpoint="$mp" $ds

# 7) マウント（-a でも個別でもOK）
zfs.exe mount $ds

# 8) 確認
zfs.exe list -o name,mountpoint,driveletter