#! /usr/bin/env bash
#
# show all users with direct or indirect relation to a (list of) given project(s)
#
# 2018 m.bernhardt@syseleven.de

if [ $BASH_VERSINFO -lt 4 ] ; then
  echo "panic: this script needs bash 4.x with support of associative arrays"
  exit 1
fi

projectids=("$@")

declare -A id2role role2id
#eval id2role=(`openstack role list -f value | sed -nEe 's/^([0-9a-z]{32}) ([-_a-zA-Z0-9]+)$/[\1]=\2/p'`)
eval role2id=(`openstack role list -f value | sed -nEe 's/^([0-9a-z]{32}) ([-_a-zA-Z0-9]+)$/[\2]=\1/p'`)

roleid_operator="${role2id[operator]}"
for projectid in ${projectids[@]} ; do
  projectname="$(openstack project show -f value -c name $projectid)"
  echo "project: $projectname ($projectid)"
  userids="$(openstack role assignment list -f value -c User -c Role --project "$projectid" | awk  '$1=="'"${roleid_operator}"'" { print $2 }' | tr "\n" " ")"
  echo "userids: $userids"
  groupids="$(openstack role assignment list -f value -c Group -c Role --project "$projectid" | awk  '$1=="'"${roleid_operator}"'" { print $2 }' | tr "\n" " ")"
  echo "groupids: $groupids"
  if [ -n "$groupids" ] ; then
    for groupid in $groupids ; do
      groupname="$(openstack group show -f value -c name $groupid)"
      echo "group: $groupname ($groupid)"
      openstack user list --group $groupid
    done
  fi
done

