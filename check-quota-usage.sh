#!/bin/bash
#
# 2018 m.bernhardt@syseleven.de
#
# Check and show quota and usage for all regions conveniently for comparison with OPENSTACK_QUOTA_COMPUTE_STACK
#
# Project xxx-xxx-stack-k8s (xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx)
# quota: CBK: xx vCPUs / xx GB RAM / xx FIPs / xx GB VS | DBL: xx vCPUs / xx GB RAM / xx FIPs / xx GB VS
# usage: CBK: xx vCPUs (x Inst.) / xx GB RAM / xx FIPs / xx GB VS | DBL: xx vCPUs (x Inst.) / xx GB RAM / xx FIPs / xx GB VS

basename="$(basename "$0")"
query_project="${1:-$OS_PROJECT_ID}"
query_regions=(cbk dbl)

openstack_version="$(openstack --version 2>&1)"
case "$openstack_version" in
  "openstack 3.16.0") ;;
  "openstack 3.17.0") ;;
  *)
  echo "WARNING: script not tested with version $openstack_version"
esac

quota_check() {
  local SAVE_OS_REGION_NAME=$OS_REGION_NAME
  local delimiter="# quota: "
  local warn_instances=""
  local warn_ram=""
  for region in "${query_regions[@]}" ; do
    export OS_REGION_NAME="$region"
    local quota=($(openstack quota show -f value -c cores -c floating-ips -c gigabytes -c instances -c ram $query_project_id))
    quota_cores="${quota[0]:-0}"
    quota_fips="${quota[1]:-0}"
    quota_vs="${quota[2]:-0}"
    quota_instances="${quota[3]:-0}"
    quota_ram="$((${quota[4]:-0}/1024))"
    if [[ ${quota_cores} != ${quota_instances} ]] ; then warn_instances="/${quota_instances}" ; fi 
    if [[ ${quota_cores} != $((quota_ram/4)) ]] ; then warn_ram="!!!" ; fi 
    echo -n "$delimiter$(echo -n "$OS_REGION_NAME" | tr "[:lower:]" "[:upper:]"): ${quota_cores} vCPUs / ${quota_ram} GB RAM${warn_ram} / ${quota_fips} FIPs / ${quota_vs} GB VS"
    delimiter=" | "
    warn_instances=""
    warn_ram=""
  done
  echo
  export OS_REGION_NAME="$SAVE_OS_REGION_NAME"
}

usage_check() {
  local SAVE_OS_REGION_NAME=$OS_REGION_NAME
  local delimiter="# usage: "
  local warn_ram=""
  for region in "${query_regions[@]}" ; do
    export OS_REGION_NAME="$region"
    local usage=($(openstack limits show --absolute -f value --project $query_project_id | sort | awk '{print $2}'))
    local volumes_size_sum="$(openstack volume list -f value -c Size --project  $query_project_id | awk '{sum+=$1} END {print sum}')" # Workaround for totalGigabytesUsed
    usage_cores="${usage[20]:-0}" # totalCoresUsed
    usage_fips="${usage[21]:-0}" # totalFloatingIpsUsed
    #usage_vs="${usage[22]:-0}" # totalGigabytesUsed (wrong)
    usage_vs="${volumes_size_sum:-0}" # Workaround for totalGigabytesUsed
    usage_instances="${usage[23]:-0}" # totalInstancesUsed
    usage_ram="$((${usage[24]:-0}/1024))" # totalRamUsed
    usage_fips=$(openstack floating ip list -f value --project $query_project_id | wc -l | sed -e 's/ //g')
    if [[ ${usage_cores} != $((usage_ram/4)) ]] ; then warn_ram="!!!" ; fi 
    echo -n "$delimiter$(echo -n "$OS_REGION_NAME" | tr "[:lower:]" "[:upper:]"): ${usage_cores} vCPUs (${usage_instances} Inst.) / ${usage_ram} GB RAM${warn_ram} / ${usage_fips} FIPs / ${usage_vs} GB VS"
    delimiter=" | "
    warn_ram=""
  done
  echo
  export OS_REGION_NAME="$SAVE_OS_REGION_NAME"
}


query_project_info=($(openstack project show -f value -c id -c name $query_project))
query_project_id="${query_project_info[0]}"
query_project_name="${query_project_info[1]}"
echo "# Project $query_project_name ($query_project_id)"

if [[ $basename =~ "quota" ]] ; then
  quota_check "${@}"
fi

if [[ $basename =~ "usage" ]] ; then
  usage_check "${@}"
fi

