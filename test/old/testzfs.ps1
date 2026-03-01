

# 1) pool ルートがドライブレターを取らないようにする
zfs.exe set driveletter=off zmtest

# 2) 反映のため export/import（wiki 推奨の流れ）
zpool.exe export zmtest
zpool.exe import zmtest

# 3) mount 状態確認
zfs.exe mount
zfs.exe list -o name,mountpoint,driveletter