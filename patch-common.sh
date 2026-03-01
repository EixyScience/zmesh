# 1) tools 配下の *.sh と tools/{zmesh,scalefs} を対象に、". ./common.sh" を安全な形へ置換
for f in tools/*.sh tools/zmesh tools/scalefs; do
  [ -f "$f" ] || continue
  # ". ./common.sh" or ". ./common.sh" の行を置換
  # 既に SCRIPT_DIR 形式に直してある場合は二重にしない
  if grep -qE '^\s*\.\s+\./common\.sh\s*$' "$f"; then
    tmp="$f.tmp.$$"
    awk '
      BEGIN{done=0}
      {
        if ($0 ~ /^[[:space:]]*\.[[:space:]]+\.\/common\.sh[[:space:]]*$/ && done==0) {
          print "SCRIPT_DIR=$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)"
          print ". \"$SCRIPT_DIR/common.sh\""
          done=1
          next
        }
        print
      }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
done

