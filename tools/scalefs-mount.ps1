param(
    [string]$Dataset,
    [string]$Mount
)

zfs set mountpoint=$Mount $Dataset
zfs mount $Dataset