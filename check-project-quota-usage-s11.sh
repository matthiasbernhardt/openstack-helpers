#!/bin/bash
#
# 2018…2021 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# Check and show quota and usage for all regions conveniently for comparison with OPENSTACK_QUOTA_COMPUTE_STACK
#
# Project xxx-xxx-stack-k8s (xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx)
# https://smith.syseleven.de/cloud/projects/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/show
# quota: CBK: xx vCPUs / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# quota: DBL: xx vCPUs / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# usage: CBK: xx vCPUs (x Inst.) / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# usage: DBL: xx vCPUs (x Inst.) / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS

basename="$(basename "$0")"
os_quota=~/repos/openstack/s11stack-manager/client/quota.py

openstack_version="$(openstack --version 2>&1)"
case "$openstack_version" in
  "openstack 3.16.0") ;;
  "openstack 3.17.0") ;;
  "openstack 4.0.0") ;;
  "openstack 6.0.0") ;;
  *)
  echo "WARNING: script not tested with version $openstack_version"
esac

bytes_to_gib() {
  local bytes="$1"
  local gib="?"
  if [[ "$bytes" == -1 ]] ; then
    gib="∞"
  elif [[ "$bytes" == 0 ]] ; then
    gib="0"
  elif [[ "$bytes" == 1 ]] ; then
    gib="0*"
  elif [[ "$bytes" =~ ^[0-9]+$ ]] ; then
    gib=$((bytes/2**30))
    local rest=$((bytes-gib*2**30))
    if [[ $rest -gt 0 ]] ; then
      gib="<$((gib+1))"
    fi
  fi
  echo "$gib"
}
# for bytes in null "" -2 -1 0 1 2 $((2**30-1)) $((2**30)) $((2**30+1)) ; do bytes_to_gib $bytes ; done

quota_check() {
  local SAVE_OS_REGION_NAME=$OS_REGION_NAME
  local delimiter="quota "
  local denotion="$(echo "$@")"
  local warn_instances=""
  local warn_cpu=""
  local warn_ram=""
  local quota_yml="$($os_quota show $query_project_id)"
  test -z "$quota_yml" && echo "quota check failed" && exit 1
  result_regions=($(echo "$quota_yml" | yq e 'keys | .[]' -))
  for region in "${result_regions[@]}" ; do
    quota_cores="$(echo "$quota_yml" | yq e ".$region"'."compute.cores"' -)"
    quota_fips="$(echo "$quota_yml" | yq e ".$region"'."network.floatingips"' -)"
    quota_vs="$(echo "$quota_yml" | yq e ".$region"'."volume.space_gb"' -)"
    quota_instances="$(echo "$quota_yml" | yq e ".$region"'."compute.instances"' -)"
    quota_ram="$(($(echo "$quota_yml" | yq e ".$region"'."compute.ram_mb"' -) /1024))"
    quota_os_bytes_q="$(echo "$quota_yml" | yq e ".$region"'.objectstorage[] | select( .type == "quobyte" ) | .space_bytes' -)"
    quota_os_bytes_c="$(echo "$quota_yml" | yq e ".$region"'.objectstorage[] | select( .type == "ceph" ) | .space_bytes' -)"
    quota_os_q="$(bytes_to_gib $quota_os_bytes_q)"
    quota_os_c="$(bytes_to_gib $quota_os_bytes_c)"
    if [[ "$quota_os_q" == "?" ]] ; then
      quota_os="$quota_os_c"
    elif [[ "$quota_os_c" == "?" ]] ; then
      quota_os="$quota_os_q"
    else
      quota_os="$quota_os_q+$quota_os_c"
    fi
    if [[ ${quota_cores} != ${quota_instances} ]] ; then warn_instances=" (${quota_instances} Inst.)" ; fi
    if [[ ${quota_cores} -gt $((quota_ram/4)) ]] ; then warn_cpu="!!!" ; fi
    if [[ ${quota_cores} -lt $((quota_ram/4)) ]] ; then warn_ram="!!!" ; fi
    echo -e "$delimiter$(echo -n "$region" | tr "[:lower:]" "[:upper:]"): ${quota_cores} vCPUs${warn_cpu}${warn_instances} / ${quota_ram} GiB RAM${warn_ram} / ${quota_fips} FIPs / ${quota_vs} GiB VS / ${quota_os} GiB OS" "$@"
    warn_instances=""
    warn_cpu=""
    warn_ram=""
  done
  export OS_REGION_NAME="$SAVE_OS_REGION_NAME"
}

usage_check() {
  local SAVE_OS_REGION_NAME=$OS_REGION_NAME
  local delimiter="usage "
  local denotion="$(echo "$@")"
  local warn_cpu=""
  local warn_ram=""
  local usage_yml="$($os_quota usage --filter compute,network,s3,objectstorage,volume $query_project_id)"
  test -z "$usage_yml" && echo "usage check failed" && exit 1
  #result_regions=($(echo "$usage_yml" | yq r -j -- - | jq -r 'keys | .[]'))
  result_regions=($(echo "$usage_yml" | yq e 'keys | .[]' -))
  for region in "${result_regions[@]}" ; do
    usage_cores="$(echo "$usage_yml" | yq e ".$region"'."compute.cores"' -)"
    usage_fips="$(echo "$usage_yml" | yq e ".$region"'."network.floatingips"' -)"
    usage_vs="$(echo "$usage_yml" | yq e ".$region"'."volume.space_gb"' -)"
    usage_instances="$(echo "$usage_yml" | yq e ".$region"'."compute.instances"' -)"
    usage_ram="$(($(echo "$usage_yml" | yq e ".$region"'."compute.ram_mb"' -) /1024))"
    usage_os_bytes_q="$(echo "$usage_yml" | yq e ".$region"'.objectstorage[] | select( .type == "quobyte" ) | .space_bytes' -)"
    usage_os_bytes_c="$(echo "$usage_yml" | yq e ".$region"'.objectstorage[] | select( .type == "ceph" ) | .space_bytes' -)"
    usage_os_q="$(bytes_to_gib $usage_os_bytes_q)"
    usage_os_c="$(bytes_to_gib $usage_os_bytes_c)"
    if [[ "$usage_os_q" == "?" ]] ; then
      usage_os="$usage_os_c"
    elif [[ "$usage_os_c" == "?" ]] ; then
      usage_os="$usage_os_q"
    else
      usage_os="$usage_os_q+$usage_os_c"
    fi
    if [[ ${usage_cores} -gt $((usage_ram/4)) ]] ; then warn_cpu="!!!" ; fi
    if [[ ${usage_cores} -lt $((usage_ram/4)) ]] ; then warn_ram="!!!" ; fi
    echo -e "$delimiter$(echo -n "$region" | tr "[:lower:]" "[:upper:]"): ${usage_cores} vCPUs${warn_cpu} (${usage_instances} Inst.) / ${usage_ram} GiB RAM${warn_ram} / ${usage_fips} FIPs / ${usage_vs} GiB VS / ${usage_os} GiB OS"
    warn_cpu=""
    warn_ram=""
  done
  #echo
  export OS_REGION_NAME="$SAVE_OS_REGION_NAME"
}

#query_project="${1:-$OS_PROJECT_ID}"
for query_project in $@ ; do
  query_project_json="$(openstack project show -f json $query_project)"
  query_project_id="$(echo "$query_project_json" | jq -r ".id")"
  query_project_name="$(echo "$query_project_json" | jq -r ".name")"
  query_project_parent_id="$(echo "$query_project_json" | jq -r ".parent_id")"
  query_project_description="$(echo "$query_project_json" | jq -r ".description")"

  if [[ "$query_project_id" == "$query_project_name" && "$query_project_parent_id" == "ccd6a18cd67945d7b6a637711a02b5d2" ]] ; then
    # syseleven-openstack-cloud / Keystone domain for customer projects (NCS)
    query_project_name="$query_project_description"
  fi

  echo "https://smith.syseleven.de/cloud/projects/${query_project_id}/show"
  echo '```'
  echo "# Project $query_project_id ($query_project_name)"

  if [ -z "$query_project_id" ] ; then continue ; fi

  if [[ $basename =~ "change" ]] ; then
    quota_check '# before'
    usage_check
    while true ; do
      read -sp '```' keypress ; printf '\r'
      quota_check '# after'
    done
  fi

  if [[ $basename =~ "quota" ]] ; then
    quota_check
  fi

  if [[ $basename =~ "usage" ]] ; then
    usage_check
  fi

  echo '```'
done

