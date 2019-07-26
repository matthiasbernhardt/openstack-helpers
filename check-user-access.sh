#! /usr/bin/env bash
#
# show all projects with direct or indirect relation to a (list of) given user(s)
#
# 2018 m.bernhardt@syseleven.de

if [ $BASH_VERSINFO -lt 4 ] ; then
  echo "panic: this script needs bash 4.x with support of associative arrays"
  exit 1
fi

userids=("$@")

declare -A id2role role2id
#eval id2role=(`openstack role list -f value | sed -nEe 's/^([0-9a-z]{32}) ([-_a-zA-Z0-9]+)$/[\1]=\2/p'`)
eval role2id=(`openstack role list -f value | sed -nEe 's/^([0-9a-z]{32}) ([-_a-zA-Z0-9]+)$/[\2]=\1/p'`)

roleid_operator="${role2id[operator]}"
for userid in ${userids[@]} ; do
  username="$(openstack user show -f value -c name $userid)"
  echo "user: $username ($userid)"

  default_project_id="$(openstack user show -f value -c default_project_id $userid)"
  if [ -n "$default_project_id" ] ; then
    default_project_name="$(openstack project show -f value -c name $default_project_id)"
    echo "default_project: $default_project_name ($default_project_id)"
  else
    echo "default_project: - (unset)"
  fi

  direct_projectids="$(openstack role assignment list -f value -c Project -c Role --user "$userid" | awk  '$1=="'"${roleid_operator}"'" { print $2 }' | tr "\n" " ")"
  echo "direct projectids: $direct_projectids"

  declare -A groupids2names
  eval groupids2names=($(openstack group list -f value --user "$userid" | sed -nEe 's/^([0-9a-z]{32}) ([-+@_.a-zA-Z0-9]+)$/[\1]=\2/p'))
  groupids="${!groupids2names[*]}"
  echo "groupids: $groupids"
  unset groups_projectids
  if [ -n "$groupids" ] ; then
    for groupid in $groupids ; do
      groupname=${groupids2names[$groupid]}
      echo "  group: $groupname ($groupid)"
      projectids="$(openstack role assignment list -f value -c Role -c Project --group "$groupid" | awk  '$1=="'"${roleid_operator}"'" { print $2 }' | tr "\n" " ")"
      echo "  group projectids: $projectids"
      groups_projectids+="$projectids"
    done
  fi

  all_projectids=$(echo $default_project_id $direct_projectids $groups_projectids | tr " " "\n" | sort | uniq | tr "\n" " ")
  echo "all projectids: $all_projectids"
  for projectid in $all_projectids ; do
    projectname="$(openstack project show -f value -c name $projectid)"
    echo "  project: $projectname ($projectid)"
  done
done

