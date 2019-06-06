#!/usr/bin/env bash

usage() {
cat <<EOF
Deployment Unit Toolkit

This toolkit provides utilities to help maintain Health API Deployment Units.
Most tools operate on a deployment unit directory, specified by a volume mount
to /du.

COMMANDS
encrypt --encryption-passphrase <secret>
decrypt --encryption-passphrase <secret>
  Encrypt or decrypt configuration and testvars files in the /du volume mount.

zip --encryption-passphrase <secret>
unzip --encryption-passphrase <secret>
  Zip or unzip configuration and testvars zip files in the /du volume mount.

dos2unix
  Fix those DOS line endings!

EXAMPLE
docker run \\
  -rm \\
  -v /my/awesome/unit:/du \\
  vasdvp/deployer-toolkit:latest encrypt --encryption-passphrase sp00py

$1
EOF
exit 1
}

#============================================================

checkVolume() {
  if [ ! -d $DU ]; then usage "Deployment unit volume not found"; fi
  local count=$(find $DU | wc -l)
  if [ "$count" == 1 ]; then usage "Deployment unit appears empty"; fi
}

doEncrypt() {
  checkVolume
  ryan-secrets encrypt-all -e "$ENCRYPTION_PASSPHRASE" -d $DU
}

doDecrypt() {
  checkVolume
  ryan-secrets decrypt-all -e "$ENCRYPTION_PASSPHRASE" -d $DU
}

doUnzip() {
  checkVolume
  cd /du
  local old=target/old-secrets-$(date +%s)
  mkdir -p $old
  for zip in *.zip
  do
    local file=${zip%*.zip}
    echo $file
    if [ -f $file ]; then mv -v $file $old; fi
    unzip -P "$ENCRYPTION_PASSPHRASE" $zip
  done
}

doZip() {
  checkVolume
  cd /du
  for zip in *.zip
  do
    local file=${zip%*.zip}
    if [ ! -f $file ];then continue; fi
    rm $zip
    echo "Creating $zip"
    zip -P "$ENCRYPTION_PASSPHRASE" $zip $file
  done
}

doDos2Unix() {
  checkVolume
  dos2unix $(find /du -type f -print0 | xargs -0 file | grep -E "ASCII .* CRLF line terminators" | cut -d : -f 1)
}

#============================================================

DU=/du
export PATH=/toolkit/bin:$PATH

ARGS=$(getopt -n $(basename ${0}) \
    -l "encryption-passphrase:,help" \
    -o "e:h" -- "$@")
[ $? != 0 ] && usage
eval set -- "$ARGS"
while true
do
  case "$1" in
    -e|--encryption-passphrase) ENCRYPTION_PASSPHRASE="$2";;
    -h|--help) usage;;
    --) shift;break;;
  esac
  shift;
done

if [ $# == 0 ]; then usage "No command specified"; fi
COMMAND=$1

case "$COMMAND" in
  e|encrypt) doEncrypt;;
  d|decrypt) doDecrypt;;
  zip) doZip;;
  unzip) doUnzip;;
  dos2unix) doDos2Unix;;
  *) usage "Unknown command: $COMMAND";;
esac
