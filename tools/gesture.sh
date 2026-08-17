#!/bin/bash
# gesture.sh drag  fx1 fy1 fx2 fy2 [steps]   — fractions of the device screen (0..1)
# gesture.sh pinch out|in [amount]           — Option-drag = two-finger pinch
# Window position is looked up every time; the Simulator window moves around.
set -e

read -r WX WY WW WH < <(osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1' | tr -d ' ' | tr ',' ' ')

# device screen inset inside the window (title bar + bezel), measured from a capture
IX=34; IY=63; SW=390; SH=849
SX=$((WX + IX)); SY=$((WY + IY))

px() { python3 -c "print(int($SX + $SW * $1))"; }
py() { python3 -c "print(int($SY + $SH * $1))"; }

case "$1" in
  drag)
    X1=$(px "$2"); Y1=$(py "$3"); X2=$(px "$4"); Y2=$(py "$5"); N=${6:-14}
    args=( "dd:$X1,$Y1" )
    for i in $(seq 1 "$N"); do
      args+=( "dm:$(( X1 + (X2-X1)*i/N )),$(( Y1 + (Y2-Y1)*i/N ))" )
    done
    args+=( "du:$X2,$Y2" )
    cliclick -e 22 "${args[@]}"
    ;;
  pinch)
    CX=$(px 0.5); CY=$(py 0.5); AMT=${3:-150}
    if [ "$2" = "out" ]; then A=20; B=$AMT; else A=$AMT; B=20; fi
    args=( "kd:alt" "dd:$((CX+A)),$CY" )
    N=14
    for i in $(seq 1 $N); do
      args+=( "dm:$(( CX + A + (B-A)*i/N )),$CY" )
    done
    args+=( "du:$((CX+B)),$CY" "ku:alt" )
    cliclick -e 25 "${args[@]}"
    ;;
  *)
    echo "usage: gesture.sh drag fx1 fy1 fx2 fy2 [steps] | gesture.sh pinch out|in [amount]" >&2
    exit 1
    ;;
esac
