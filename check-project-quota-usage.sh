#!/bin/bash
#
# 2018…2025 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# Check and show quota and usage for all regions conveniently for comparison with OPENSTACK_QUOTA_COMPUTE_STACK
#
# Project customer-project (xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx)
# quota AAA: xx vCPUs / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# quota BBB: xx vCPUs / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# usage AAA: xx vCPUs (x Inst.) / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS
# usage BBB: xx vCPUs (x Inst.) / xx GiB RAM / xx FIPs / xx GiB VS / xx GiB OS

basename="$(basename "$0")"
query_project="${1:-$OS_PROJECT_ID}"
#query_regions=(aaa bbb ccc yyy zzz)
query_regions=($(openstack region list -f value -c Region | grep -v infra))

os_quota=quota.py

openstack_version="$(openstack --version 2>&1)"
case "$openstack_version" in
  "openstack 3.16.0") ;;
  "openstack 3.17.0") ;;
  "openstack 4.0.0") ;;
  "openstack 6.0.0") ;;
  "openstack 8.0.0") ;;
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

bytes_to_tib() {
  local bytes="$1"
  local tib="?"
  if [[ "$bytes" == -1 ]] ; then
    tib="∞"
  elif [[ "$bytes" == 0 ]] ; then
    tib="0"
  elif [[ "$bytes" == 1 ]] ; then
    tib="0*"
  elif [[ "$bytes" =~ ^[0-9]+$ ]] ; then
    tib=$((bytes/2**40))
    local rest=$((bytes-tib*2**40))
    if [[ $rest -gt 0 ]] ; then
      tib="<$((tib+1))"
    fi
  fi
  echo "$tib"
}
# for bytes in null "" -2 -1 0 1 2 $((2**40-1)) $((2**40)) $((2**40+1)) ; do bytes_to_tib $bytes ; done

scaled_round() {
  local bytes="$1"
  #local s=2 # 2**2 = 4 ; round to 2**(e-s), e.g. 513 GiB -> 768 GiB
  local s=3 # 2**3 = 8 ; round to 2**(e-s), e.g. 513 GiB -> 640 GiB
  #local s=4 # 2**4 = 16 ; round to 2**(e-s), e.g. 513 GiB -> 576 GiB
  local ps=$((2**s))
  local exp=$((39-s)) # 2**39 = 512 MiB
  local log=$(((bytes-1)/2**exp))
  while [[ $log -gt $ps ]] ; do
    log=$(((bytes-1)/2**(++exp)))
  done
  echo $(((log+1)*2**exp))
}
# for bytes in 1 $((2**39)) $((2**39+1)) $((2**39+2**36+1)) $((2**39+2**37+1)) $((2**39+2**38+1)) $((2**40-1)) $((2**40)) $((2**40+1)) $((2**44)) $((2**44+1)) ; do scaled_round $bytes ; done

suggest_appropriate_rounded_quota() {
  local usage="$1"
  local bytes=$(( $usage * 5 / 3 ))
  if [[ $bytes -lt $((512*2**30)) ]] ; then # < 512 MiB
    echo "$((512*2**30))" # 512 MiB
    return
  fi
  scaled_round $bytes
}
# for bytes in null "" -2 -1 0 1 2 $((2**39)) $((2**39+1)) $((2**39+2**36+1)) $((2**39+2**37+1)) $((2**39+2**38+1)) $((2**40-1)) $((2**40)) $((2**40+1)) $((2**44)) $((2**44+1)) ; do suggest_appropriate_rounded_quota $bytes ; done

generate_ceph_quota_set_cmd() {
  local bytes="$1"
  local gib="$(bytes_to_gib $bytes)"
  local tib="$(bytes_to_tib $bytes)"
  #echo "$bytes B = $gib GiB = $tib TiB"
  if [[ "$tib" =~ ^[0-9]+$ ]] ; then
    echo "$os_quota set --regions ccc $query_project_name --objectstorage ceph,\$(($tib*2**40)) # $tib TiB = $bytes B"
  elif [[ "$gib" =~ ^[0-9]+$ ]] ; then
    echo "$os_quota set --regions ccc $query_project_name --objectstorage ceph,\$(($gib*2**30)) # $gib GiB = $bytes B"
  else
    echo "$os_quota set --regions ccc $query_project_name --objectstorage ceph,$bytes"
  fi
}

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
    if [ -n "$filter_regions" ] && ! [[ "$region" =~ $filter_regions ]] ; then continue ; fi
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
  if [ "$abc" = y ] ; then generate_ceph_quota_set_cmd "$(echo "$quota_yml" | yq e ".ccc"'.objectstorage[] | select( .type == "ceph" ) | .space_bytes' -)" ; fi
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
  result_regions=($(echo "$usage_yml" | yq e 'keys | .[]' -))
  for region in "${result_regions[@]}" ; do
    if [ -n "$filter_regions" ] && ! [[ "$region" =~ $filter_regions ]] ; then continue ; fi
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
  if [ "$abc" = y ] ; then generate_ceph_quota_set_cmd $( suggest_appropriate_rounded_quota $(echo "$usage_yml" | yq e ".ccc"'.objectstorage[] | select( .type == "ceph" ) | .space_bytes' -)) ; fi
  export OS_REGION_NAME="$SAVE_OS_REGION_NAME"
}

projects_json="$(openstack project list --long -f json)"
if [ -z "$projects_json" ] || ! [ "$(echo $projects_json | jq 'length')" -gt 0 ] ; then exit 1 ; fi
match_projects() {
  pattern="$1"

  # exact match unique id
  project_id="$(echo "$projects_json" | jq -r '.[] | select(.ID == "'"$pattern"'") | .ID' )"
  if [ -n "$project_id" -a "$(echo "$project_id" | wc -l)" -eq 1 ] ; then
    echo "$project_id"
    return
  fi

  # exact matches name
  project_ids=($(echo "$projects_json" | jq -r '.[] | select(.Name == "'"$pattern"'") | .ID' ))

  # exact matches description project_name (XYZ)
  # "Description": "{\"organization_name\": \"org\", \"project_name\": \"prj\"}",
  project_ids+=($(echo "$projects_json" | jq -r '.[] | select(."Domain ID" == "0123456789abcdef0123456789abcdef") | select(.Description | fromjson | .project_name=="'"$pattern"'") | .ID' ))

  # exact matches description organization_name (XYZ)
  project_ids+=($(echo "$projects_json" | jq -r '.[] | select(."Domain ID" == "0123456789abcdef0123456789abcdef") | select(.Description | fromjson | .organization_name=="'"$pattern"'") | .ID' ))

  if [ -n "$project_ids" ] ; then
    echo "${project_ids[@]}"
    return
  fi

  # pattern matches name
  project_ids=($(echo "$projects_json" | jq -r '.[] | select(.Name | match("'"$pattern"'")) | .ID' ))

  # pattern matches description project_name (XYZ)
  project_ids+=($(echo "$projects_json" | jq -r '.[] | select(."Domain ID" == "0123456789abcdef0123456789abcdef") | select(.Description | fromjson | .project_name | match("'"$pattern"'")) | .ID' ))

  # pattern matches description organization_name (XYZ)
  project_ids+=($(echo "$projects_json" | jq -r '.[] | select(."Domain ID" == "0123456789abcdef0123456789abcdef") | select(.Description | fromjson | .organization_name | match("'"$pattern"'")) | .ID' ))

  if [ -n "$project_ids" ] ; then
    echo "${project_ids[@]}"
    return
  fi

  # pattern matches description
  project_ids=($(echo "$projects_json" | jq -r '.[] | select(."Domain ID" == "0123456789abcdef0123456789abcdef") | select(.Description | match("'"$pattern"'")) | .ID' ))

  if [ -n "$project_ids" ] ; then
    echo "${project_ids[@]}"
    return
  fi

  return 1
}

for query_pattern in $@ ; do
  if ! query_project_ids="$(match_projects "$query_pattern")" ; then
    echo "no matches for '$query_pattern'"
    continue
  fi

  for query_project_id in $query_project_ids ; do
    if ! query_project_json="$(echo "$projects_json" | jq '.[] | select (.ID == "'"$query_project_id"'")' )" ; then continue ; fi
    query_project_id="$(echo "$query_project_json" | jq -r ".ID")"
    query_project_name="$(echo "$query_project_json" | jq -r ".Name")"
    query_project_domain_id="$(echo "$query_project_json" | jq -r '."Domain ID"')"
    query_project_description="$(echo "$query_project_json" | jq -r ".Description")"

    if [ -z "$query_project_id" ] ; then continue ; fi

    unset xyz abc filter_regions
    if [[ "$query_project_id" == "$query_project_name" && "$query_project_domain_id" == "0123456789abcdef0123456789abcdef" ]] ; then
      xyz=y # new cloud regions
      query_project_info="$query_project_description"
      filter_regions="(yyy|zzz)"
    else
      abc=y # old cloud regions
      query_project_info="$query_project_name"
      filter_regions="(aaa|bbb|ccc)"
    fi

    echo '```'
    echo "# Project $query_project_id ($query_project_info)"

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
done

