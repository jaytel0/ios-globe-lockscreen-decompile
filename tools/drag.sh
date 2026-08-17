#!/bin/bash
# drag.sh x1 y1 x2 y2 [steps]  — one cliclick invocation so mouse-down persists
X1=$1; Y1=$2; X2=$3; Y2=$4; N=${5:-12}
args=( "dd:$X1,$Y1" )
for i in $(seq 1 $N); do
  x=$(( X1 + (X2-X1)*i/N )); y=$(( Y1 + (Y2-Y1)*i/N ))
  args+=( "dm:$x,$y" )
done
args+=( "du:$X2,$Y2" )
cliclick -e 22 "${args[@]}"
