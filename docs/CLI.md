# zmesh CLI manual

短縮オプション仕様
short
long
-i
interactive
-r
root
-n
name
-a
alias
-c
config

## initialization

zmesh-init.ps1

interactive:

zmesh-init.ps1 -Interactive

---

## add scalefs root

add-root.ps1

example:

add-root.ps1 -Path D:\scalefs -Alias fast

---

## create scalefs

add-scalefs.ps1

example:

add-scalefs.ps1 -Root D:\scalefs -Name photos

---

## list scalefs

list-scalefs.ps1

---

## doctor

doctor.ps1


