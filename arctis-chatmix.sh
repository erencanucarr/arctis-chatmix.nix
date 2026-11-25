sink="${ARCTIS_SINK:-}"
set_default="${ARCTIS_SET_DEFAULT:-1}"
game_label="${ARCTIS_GAME_LABEL:-Arctis Game}"
chat_label="${ARCTIS_CHAT_LABEL:-Arctis Chat}"
state="${XDG_RUNTIME_DIR:-/tmp}/arctis-chatmix"
loops=()

hid() {
  for h in /sys/class/hidraw/hidraw*; do
    grep -q 'HID_ID=0003:00001038:0000220E' "$h/device/uevent" 2>/dev/null || continue
    if [ "$(cat "$h/device/../bInterfaceNumber" 2>/dev/null)" = "$1" ]; then
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
  pw-dump 2>/dev/null | jq -r 'first(.[] | .info.props? // {} | select(."media.class" == "Audio/Sink" and ((."node.name" // "") | startswith("alsa_output.usb-SteelSeries_Arctis_7_"))) | ."node.name") // empty' || true
}

start_loops() {
  for kind in "game:$game_label" "chat:$chat_label"; do
    n=${kind%%:*}
    pw-loopback -n "arctis_$n" \
      --capture-props="media.class=Audio/Sink node.name=arctis_$n node.description=\"${kind#*:}\" audio.position=[FL,FR]" \
      --playback-props="node.name=arctis_$n.out target.object=$1 node.passive=true node.dont-fallback=true stream.dont-remix=true audio.position=[FL,FR]" &
    loops+=("$!")
  done
}

stop_loops() {
  if [ "${#loops[@]}" -gt 0 ]; then
    kill "${loops[@]}" 2>/dev/null || true
  fi
  loops=()
  echo off > "$state"
}

apply() {
  if [ -n "$game_id" ]; then wpctl set-volume "$game_id" "$1%" || true; fi
  if [ -n "$chat_id" ]; then wpctl set-volume "$chat_id" "$2%" || true; fi
  echo "$1 $2" > "$state"
}

initial() {
  { sleep 0.3; printf '\x00\xb0' > "$1"; } &
  while read -r id _ _ _ g c _; do
    if [ "$id" = "b0" ]; then
      echo "$(( 16#$g )) $(( 16#$c ))"
      return
    fi
  done < <(timeout 2 stdbuf -oL od -An -tx1 -w64 -v "$1")
  echo "100 100"
}

trap 'stop_loops; exit 0' TERM INT

while true; do
  if ! events=$(hid 05) || ! status=$(hid 03) || ! target=$(find_sink) || [ -z "$target" ]; then
    sleep 10
    continue
  fi

  start_loops "$target"
  game_id="" chat_id="" game_sink=""
  for _ in $(seq 50); do
    IFS=, read -r game_id chat_id game_sink < <(ids arctis_game.out arctis_chat.out arctis_game) || true
    [ -n "$game_id" ] && [ -n "$chat_id" ] && [ -n "$game_sink" ] && break
    sleep 0.2
  done
  if [ "$set_default" = 1 ] && [ -n "$game_sink" ]; then
    wpctl set-default "$game_sink" || true
  fi

  read -r g c < <(initial "$status")
  apply "$g" "$c"

  while read -r id g c _; do
    [ "$id" = "45" ] && apply "$(( 16#$g ))" "$(( 16#$c ))"
  done < <(stdbuf -oL od -An -tx1 -w64 -v "$events")

  stop_loops
  sleep 2
done
