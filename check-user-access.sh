#! /usr/bin/env bash
#
# 2018…2021 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# show all projects with direct or indirect relation to a (list of) given user(s)

if [ $BASH_VERSINFO -lt 4 ] ; then
  echo "panic: this script needs bash 4.x with support of associative arrays"
  exit 1
fi

users=("$@")

for user in ${users[@]} ; do
  user_json="$(openstack user show -f json $user)"
  user_id="$(echo "$user_json" | jq -r ".id")"
  user_name="$(echo "$user_json" | jq -r ".name")"
  user_enabled="$(echo "$user_json" | jq -er ".enabled")" || unset user_enabled
  # if [ ! $? ] ; then echo unset user_enabled ; fi
  default_project_id="$(echo "$user_json" | jq -er ".default_project_id")" || unset default_project_id
  # if [ ! $? ] ; then unset default_project_id ; fi
  echo "user: ${user_name} (${user_id}, enabled:${user_enabled})"

  if [ -z "$user_name" -o -z "$user_id" ] ; then continue ; fi

  if [ -n "$default_project_id" ] ; then
    default_project_name="$(openstack project show -f value -c name $default_project_id)"
    echo "default_project: $default_project_name ($default_project_id)"
    echo "# ~/repos/openstack/s11stack-manager/client/purge-project.py --all-regions --keep-users --keep-groups --keep-project $default_project_id # $default_project_name"
  else
    echo "default_project: - (unset)"
  fi

  echo "# openstack application credential list --user $user_name"
  echo "# openstack credential list --user $user_name"

  # TODO: ssh keys, tokens
  # for region in ${regions[@]} ; do
  #   openstack --os-region $region --os-username $user_id --os-password $password --os-project-id '' --os-project-name $projectname keypair list
  # done

  direct_projectids="$(openstack role assignment list -f value -c Project --user "$user_id" | sort | uniq | tr "\n" " ")"
  echo "direct projectids: $direct_projectids"

  declare -A groupids2names
  eval groupids2names=($(openstack group list -f value --user "$user_id" | sed -nEe 's/^([0-9a-z]{32}) ([-+@_.a-zA-Z0-9]+)$/[\1]=\2/p'))
  groupids="${!groupids2names[*]}"
  echo "groupids: $groupids"
  unset groups_projectids
  if [ -n "$groupids" ] ; then
    for groupid in $groupids ; do
      groupname=${groupids2names[$groupid]}
      echo "  group: $groupname ($groupid)"
      group_member_count=$(openstack user list --group $groupid -f value | wc -l)
      if [ $group_member_count -le 1 ] ; then
        echo "    # openstack group remove user $groupname $user_name # POTENTIALLY ABANDONED"
        echo "    # openstack user list --group $groupid # $groupname"
      else
        echo "    # openstack group remove user $groupname $user_name"
      fi
      projectids="$(openstack role assignment list -f value -c Project --group "$groupid" | sort | uniq | tr "\n" " ")"
      echo "  group projectids: $projectids"
      groups_projectids+="$projectids"
    done
  fi

  all_projectids=$(echo $default_project_id $direct_projectids $groups_projectids | tr " " "\n" | sort | uniq | tr "\n" " ")
  echo "all projectids: $all_projectids"
  for project_id in $all_projectids ; do
    project_json="$(openstack project show -f json $project_id)"
    project_id="$(echo "$project_json" | jq -r ".id")"
    project_name="$(echo "$project_json" | jq -r ".name")"
    project_parent_id="$(echo "$project_json" | jq -r ".parent_id")"
    project_description="$(echo "$project_json" | jq -r ".description")"

    if [[ "$project_id" == "$project_name" ]] ; then
      # syseleven-openstack-cloud / Keystone domain for customer projects (NCS)
      project_name="$project_description"
    fi
    echo "  project: $project_name ($project_id)"
  done

done

