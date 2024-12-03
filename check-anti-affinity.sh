#! /bin/bash
#
# 2024-01-09 m.bernhardt@syseleven.de
#

case "$1" in "-v"|"-d" ) debug="y" ; shift ;; "-q" ) debug="n" ; shift ;; esac
#if [ -z "$debug" ] ; then if tty -s ; then debug="y" ; fi ; fi
dcat() { if [ "$debug" != "y" ] ; then cat > /dev/null ; else cat ; fi ; }
icat() { if [ "$debug" == "n" ] ; then cat > /dev/null ; else cat ; fi ; }
decho() { echo "$@" | dcat ; }
iecho() { echo "$@" | icat ; }
dexec() { decho "$@" > /dev/stderr ; "$@" ; }
dsexec() { decho "$@" > /dev/stderr ; "$@" 2> /dev/null ; }

if [[ "$1" == "--project" ]] ; then # query another project, for admin only
  project="$2"
  shift 2
  param_project="--project $project"
fi

state="OK"
rc=0

server_list="$(dexec openstack server list $param_project -f value -c ID -c Name)"
for infix in "$@" ; do
  decho "infix: '$infix'"
  id_prefix_list="$(echo "$server_list" | sed -nEe 's/(.{36} .*)'"$infix"'.*$/\1/p')"
  decho "id_prefix_list: $id_prefix_list"
  IFS="$(echo)"
  prefixes=($(echo "$id_prefix_list" | cut -d " " -f 2 | sort | uniq))
  unset IFS
  decho "prefixes:" ${prefixes[@]} "(${#prefixes[@]})"
  for prefix in ${prefixes[@]} ; do
    decho "prefix: '$prefix'"
    ids=$(echo "$id_prefix_list" | awk 'BEGIN {ORS=" "} $2=="'$prefix'" {print $1}')
    decho "ids:" $ids
    hostids=$(
      for id in $ids ; do
        dexec openstack server show -f value -c hostId $id
      done
    )
    decho "hostids:" $hostids
    truckfactor=$(echo "$hostids" | sort | uniq -c | awk '{print $1}' | sort -rn | head -n 1)
    decho "truckfactor: $truckfactor"
    message="For $prefix$infix there are max $truckfactor instances on one hypervisor"
    decho "messages+=$message"
    messages+="${messages:+", "}for $prefix$infix there are max $truckfactor instances on same hypervisor"
    if [ "$truckfactor" -gt 1 ] ; then
      state="CRITICAL"
      rc=3
    fi
  done
done

echo $state ${messages:+": $messages"}
exit $rc

