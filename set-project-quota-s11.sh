#! /bin/bash
#
# 2023 m.bernhardt@syseleven.de
#
# set quota for all regions conveniently using the output of stackmanager as input
#

os_quota=~/repos/openstack/s11stack-manager/client/quota.py

while [ $# -gt 0 ] ; do
  case "$1" in
    -p) projects+=("$2") ; shift 2 ; continue ;;
    -q) quota_files+=("$2") ; shift 2 ; continue ;;
    *) echo "excess parameter(s): $@" ; exit 1 ;;
  esac
done

for project in ${projects[@]} ; do
  project_info=($(openstack project show -f value -c id -c name $project))
  project_id="${project_info[0]}"
  project_name="${project_info[1]}"
  echo "project: $project_name ($project_id)"
  if [ -z "$project_id" ] ; then continue ; fi
  for quota_file in "${quota_files[@]}" ; do 
    echo "quota: $quota_file"
    quota_yml="$(cat $quota_file)"
    regions=($(echo "$quota_yml" | yq e 'keys | .[]'))
    for region in "${regions[@]}" ; do
      region_quota_yml="$(echo "$quota_yml" | yq ".$region")"
      echo $region: $region_quota_yml
      $os_quota set $project_id --regions $region $region_quota_yml
    done
  done
done

