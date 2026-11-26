sink="${ARCTIS_SINK:-}"
set_default="${ARCTIS_SET_DEFAULT:-1}"
link_volume="${ARCTIS_LINK_VOLUME:-1}"
game_label="${ARCTIS_GAME_LABEL:-Arctis Game}"
chat_label="${ARCTIS_CHAT_LABEL:-Arctis Chat}"
state="${XDG_RUNTIME_DIR:-/tmp}/arctis-chatmix"
battery="$state.battery"
products="0x220e 0x2212 0x2216 0x2236"
pids=()

hid() {
  for h in /sys/class/hidraw/hidraw*; do
    id=$(grep -o 'HID_ID=0003:00001038:0000....' "$h/device/uevent" 2>/dev/null) || continue
    id="0x${id: -4}"
    [[ " $products " == *" ${id,,} "* ]] || continue
    if [ -z "$1" ] || [ "$(cat "$h/device/../bInterfaceNumber" 2>/dev/null)" = "$1" ]; then
      echo "/dev/${h##*/}"
      return 0
    fi
  done
  return 1
}

ids() {
  pw-dump 2>/dev/null | jq -r '[$ARGS.positional[] as $n | first(.[] | select(.info.props."node.name" == $n) | .id) // "" | tostring] | join(",")' --args "$@" || true
}

find_sink() {
  if [ -n "$sink" ]; then
    [ -n "$(ids "$sink")" ] && echo "$sink"
    return 0
  fi
  read -ra p <<< "$products"
  pw-dump 2>/dev/null | jq -r '([.[] | select(.info.props?."media.class" == "Audio/Device" and .info.props."device.vendor.id" == "0x1038" and (.info.props."device.product.id" | IN($ARGS.positional[]))) | .id]) as $d | first(.[] | .info.props? // {} | select(."media.class" == "Audio/Sink" and (."device.id" | IN($d[]))) | ."node.name") // empty' --args "${p[@]}" || true
}

start_loops() {
  for kind in "game:$game_label" "chat:$chat_label"; do
    n=${kind%%:*}
    pw-loopback -n "arctis_$n" \
      --capture-props="media.class=Audio/Sink node.name=arctis_$n node.description=\"${kind#*:}\" audio.position=[FL,FR]" \
      --playback-props="node.name=arctis_$n.out target.object=$1 node.passive=true node.dont-fallback=true stream.dont-remix=true audio.position=[FL,FR]" &
    pids+=("$!")
  done
}

stop_loops() {
  if [ "${#pids[@]}" -gt 0 ]; then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
  pids=()
  echo off > "$state"
  rm -f "$battery"
}

apply() {
  if [ -n "$game_id" ]; then wpctl set-volume "$game_id" "$1%" || true; fi
  if [ -n "$chat_id" ]; then wpctl set-volume "$chat_id" "$2%" || true; fi
  echo "$1 $2" > "$state"
}

initial() {
  { sleep 0.3; printf '\x00\xb0' > "$1"; } &
  while read -r id on lvl chg g c _; do
    if [ "$id" = "b0" ]; then
      if [ "$on" = 01 ]; then on=false; else on=true; fi
      if [ "$chg" = 01 ]; then chg=true; else chg=false; fi
      echo "$on $(level "$lvl") $chg $(( 16#$g )) $(( 16#$c ))"
      return
    fi
  done < <(timeout 2 stdbuf -oL od -An -tx1 -w64 -v "$1")
  echo "false null false 100 100"
}

level() {
  local l=$(( 16#$1 * 25 ))
  echo $(( l > 100 ? 100 : l ))
}

power() {
  printf '{"connected":%s,"charging":%s,"level":%s}\n' "$on" "$chg" "$lvl" > "$battery"
  echo "battery: connected=$on charging=$chg level=$lvl ($1)" >&2
}

wheel() {
  on=$2 chg=$3 lvl=$4
  power b0
  exec 3< <(exec stdbuf -oL od -An -tx1 -w64 -v "$1")
  sub=$!
  trap 'kill "$sub" 2>/dev/null; exit 0' TERM
  while read -r id a b _ <&3; do
    case "$id" in
      45) apply "$(( 16#$a ))" "$(( 16#$b ))" ;;
      b7)
        lvl=$(level "$a")
        power "b7 $a"
        ;;
      b9)
        if [ "$a" = 01 ]; then on=false; else on=true; fi
        power "b9 $a"
        ;;
      bb)
        case "$a" in
          00) on=false chg=false ;;
          01) on=true chg=true ;;
          *) on=true chg=false ;;
        esac
        power "bb $a"
        ;;
    esac
  done
}

mirror() {
  v=$(wpctl get-volume "$game_sink" 2>/dev/null) || return 0
  [ "$v" = "$last" ] && return 0
  last=$v
  read -r _ vol _ <<< "$v"
  wpctl set-volume "$chat_sink" "$vol" || true
  if [[ "$v" == *MUTED* ]]; then m=1; else m=0; fi
  wpctl set-mute "$chat_sink" "$m" || true
}

link() {
  exec 4< <(exec pactl subscribe 2>/dev/null)
  sub=$!
  trap 'kill "$sub" 2>/dev/null; exit 0' TERM
  idx=""
  while read -r i n _; do
    [ "$n" = arctis_game ] && idx=$i
  done < <(pactl list short sinks 2>/dev/null || true)
  [ -n "$idx" ] || return 0
  last=""
  mirror
  while read -r ev <&4; do
    [ "$ev" = "Event 'change' on sink #$idx" ] || continue
    while read -r -t 0.05 _ <&4; do :; done
    mirror
  done
}

trap 'stop_loops; exit 0' TERM INT

hid "" > /dev/null || exit 0

while true; do
  target=""
  for _ in $(seq 15); do
    hid "" > /dev/null || { stop_loops; exit 0; }
    if events=$(hid 05) && status=$(hid 03) && target=$(find_sink) && [ -n "$target" ]; then
      break
    fi
    target=""
    sleep 1
  done
  if [ -z "$target" ]; then
    echo "headset sink not found in PipeWire" >&2
    stop_loops
    exit 1
  fi

  start_loops "$target"
  game_id="" chat_id="" game_sink="" chat_sink=""
  for _ in $(seq 50); do
    IFS=, read -r game_id chat_id game_sink chat_sink < <(ids arctis_game.out arctis_chat.out arctis_game arctis_chat) || true
    [ -n "$game_id" ] && [ -n "$chat_id" ] && [ -n "$game_sink" ] && [ -n "$chat_sink" ] && break
    sleep 0.2
  done
  if [ "$set_default" = 1 ] && [ -n "$game_sink" ]; then
    wpctl set-default "$game_sink" || true
  fi

  read -r on lvl chg g c < <(initial "$status")
  apply "$g" "$c"

  wheel "$events" "$on" "$chg" "$lvl" &
  pids+=("$!")
  if [ "$link_volume" = 1 ] && [ -n "$game_sink" ] && [ -n "$chat_sink" ]; then
    link &
    pids+=("$!")
  fi

  wait -n "${pids[@]:0:3}" || true
  stop_loops
  hid "" > /dev/null || exit 0
  sleep 1
done
