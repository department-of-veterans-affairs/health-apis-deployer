

usage() {
cat<<EOF
$0 [options]
Increment and decrement LB rules not by hand. Takes in 3 args, MAX, MIN, and DELTA.
This will search through the directory specified and look for all .conf files.
Anything within the MAX and MIN priority (inclusive) will be changed by the delta.
You can move rules down in priority with the decrement flag. This assumes to be
working off of pwd by default.
Options:
 --debug                       Enable debugging output
 -d, --directory <dir>         What directory to look in
 -m, --decrement               Decrement (m)inus the delta
 -h, --help                    Display this help and exit

$1
EOF
  exit 1
}

DIRECTORY=$(pwd)
MODIFIER=1

ARGS=$(getopt -n $(basename ${0}) \
    -l "debug,help,directory,decrement" \
    -o "hd:m" -- "$@")
[ $? != 0 ] && usage
eval set -- "$ARGS"
while true
do
  case "$1" in
    --debug) set -x;;
    -d|--directory) DIRECTORY=$(pwd)/$2;;
    -m|--decrement) MODIFIER=-1;;
    -h|--help) usage "How does this work";;
    --) shift;break;;
  esac
  shift;
done

MIN=$1
MAX=$2
DELTA=$3
PRIORITY_REGEX=".*\[([0-9]{2,3})"

((DELTA = $DELTA * $MODIFIER))

if (( $MIN >= $MAX )); then
  usage "Why did you do this? Max: $MAX, Min: $MIN"
fi

echo $DIRECTORY

#Force these results to be an array so we can go line by line. Also cuts off after the
#priority because we don't need it
LB_RULES=($(grep -nr --include="*.conf" "DU_LOAD_BALANCER_RULES" $DIRECTORY | sed 's/].*//'))

#Example line (start abbreviated): ../products/qms.conf:9:DU_LOAD_BALANCER_RULES[860
for LINE in "${LB_RULES[@]}"; do
  #Splits string into an array on : as a delimiter. Works by replacing the colon with a space
  #to cause the string to be chunked like this, as I understand it
  #https://www.linuxquestions.org/questions/programming-9/bash-shell-script-split-array-383848/#post3270796
  PARTS=(${LINE//:/ })
  FILE=${PARTS[0]}
  LINE_NUM=${PARTS[1]}

  #This feels like a gross way to do this, might have been better to just filter this through some stuff
  [[ "${PARTS[2]}" =~ .*\[([0-9]{2,3}) ]]
  PRIORITY=${BASH_REMATCH[1]}

  #Are we in the range
  if (( $PRIORITY >= $MIN )) && (( $PRIORITY <= $MAX )); then
    ((NEW_PRIORITY= $PRIORITY + $DELTA))
    echo $NEW_PRIORITY
  fi

done
