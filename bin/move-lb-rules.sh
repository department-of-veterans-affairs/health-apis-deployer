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
PRIORITY_REGEX=".*\[(\d{2,3})\].*"

((DELTA = $DELTA * $MODIFIER))

echo $DIRECTORY

#Force these results to be an array so we can go line by line
LB_RULES=($(grep -nro --include="*.conf" "DU_LOAD_BALANCER_RULES" $DIRECTORY))

for LINE in "${LB_RULES[@]}"; do
  PARTS=(${LINE//:/ })
  FILE=${PARTS[0]}
  LINE_NUM=${PARTS[1]}
  [[ "${PARTS[2]}" =~ $PRIORITY_REGEX ]]
  echo ${BASH_REMATCH[1]}
done
