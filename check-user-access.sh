#! /usr/bin/env bash
#
# 2018…2026 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# show all projects with direct or indirect relation to a (list of) given user(s)

if [ $BASH_VERSINFO -lt 4 ] ; then
  echo "panic: this script needs bash 4.x with support of associative arrays"
  exit 1
fi

users_json="$(openstack user list --long -f json)"
if [ -z "$users_json" ] || ! [ "$(echo $users_json | jq 'length')" -gt 0 ] ; then exit 1 ; fi
match_users() {
  pattern="$1"

  # exact match unique id
  user_id="$(echo "$users_json" | jq -r '.[] | select(.ID == "'"$pattern"'") | .ID' )"
  if [ -n "$user_id" -a "$(echo "$user_id" | wc -l)" -eq 1 ] ; then
    echo "$user_id"
    return
  fi

  # exact matches name
  user_ids=($(echo "$users_json" | jq -r '.[] | select(.Name == "'"$pattern"'") | .ID' ))

  # exact matches email
  new_user_ids=$(echo "$users_json" | jq -r '.[] | select(.Email == "'"$pattern"'") | .ID' )
  for user_id in $new_user_ids ; do
    if ! echo "${user_ids[@]}" | xargs -n 1 | egrep  "^$user_id\$" > /dev/null ; then
      user_ids+=($user_id)
    fi
  done

  # exact matches description
  new_user_ids=$(echo "$users_json" | jq -r '.[] | select(.Description == "'"$pattern"'") | .ID' )
  for user_id in $new_user_ids ; do
    if ! echo "${user_ids[@]}" | xargs -n 1 | egrep  "^$user_id\$" > /dev/null ; then
      user_ids+=($user_id)
    fi
  done

  if [ -n "$user_ids" ] ; then
    echo "${user_ids[@]}"
    return
  fi

  # pattern matches name
  user_ids=($(echo "$users_json" | jq -r '.[] | select(.Name | match("'"$pattern"'")) | .ID' ))

  # pattern matches email
  new_user_ids=$(echo "$users_json" | jq -r '.[] | select(.Email) | select (.Email | match("'"$pattern"'")) | .ID' )
  for user_id in $new_user_ids ; do
    if ! echo "${user_ids[@]}" | xargs -n 1 | egrep  "^$user_id\$" > /dev/null ; then
      user_ids+=($user_id)
    fi
  done

  # pattern matches description
  new_user_ids=$(echo "$users_json" | jq -r '.[] | select(.Description) | select (.Description | match("'"$pattern"'")) | .ID' )
  for user_id in $new_user_ids ; do
    if ! echo "${user_ids[@]}" | xargs -n 1 | egrep  "^$user_id\$" > /dev/null ; then
      user_ids+=($user_id)
    fi
  done

  if [ -n "$user_ids" ] ; then
    echo "${user_ids[@]}"
    return
  fi

  return 1
}

for query_pattern in "$@" ; do
  if ! query_user_ids="$(match_users "$query_pattern")" ; then
    echo "no matches for '$query_pattern'"
    continue
  fi

  for query_user_id in $query_user_ids ; do
    if ! query_user_json="$(echo "$users_json" | jq '.[] | select (.ID == "'"$query_user_id"'")' )" ; then continue ; fi
    query_user_id="$(echo "$query_user_json" | jq -r ".ID")"
    query_user_name="$(echo "$query_user_json" | jq -r ".Name")"
    query_user_domain_id="$(echo "$query_user_json" | jq -r '."Domain"')"
    query_user_description="$(echo "$query_user_json" | jq -r ".Description")" || unser query_user_description
    query_user_project_id="$(echo "$query_user_json" | jq -re ".Project")" || unset query_user_project_id
    query_user_email="$(echo "$query_user_json" | jq -re ".Email")" || unset query_user_email
    query_user_enabled="$(echo "$query_user_json" | jq -re ".Enabled")" || unset query_user_enabled

    echo "user: ${query_user_name} (${query_user_id}, enabled:${query_user_enabled})"

    if [ -z "$query_user_name" -o -z "$query_user_id" ] ; then continue ; fi

    if [ -n "$query_user_project_id" ] ; then
      default_project_name="$(openstack project show -f value -c name $query_user_project_id)"
      echo "default_project: $default_project_name ($query_user_project_id)"
      echo "# ~/repos/openstack/s11stack-manager/client/purge-project.py --all-regions --keep-users --keep-groups --keep-project $query_user_project_id # $default_project_name"
    else
      echo "default_project: - (unset)"
    fi

    echo "# openstack application credential list --user $query_user_name"
    echo "# openstack credential list --user $query_user_name"

    # TODO: ssh keys, tokens
    # for region in ${regions[@]} ; do
    #   openstack --os-region $region --os-username $query_user_id --os-password $password --os-project-id '' --os-project-name $projectname keypair list
    # done

    direct_projectids="$(openstack role assignment list -f value -c Project --user "$query_user_id" | sort | uniq | tr "\n" " ")"
    echo "direct projectids: $direct_projectids"

    declare -A groupids2names
    eval groupids2names=($(openstack group list -f value --user "$query_user_id" | sed -nEe 's/^([0-9a-z]{32}) ([-+@_.a-zA-Z0-9]+)$/[\1]=\2/p'))
    groupids="${!groupids2names[*]}"
    echo "groupids: $groupids"
    unset groups_projectids
    if [ -n "$groupids" ] ; then
      for groupid in $groupids ; do
        groupname=${groupids2names[$groupid]}
        echo "  group: $groupname ($groupid)"
        group_member_count=$(openstack user list --group $groupid -f value | wc -l)
        if [ $group_member_count -le 1 ] ; then
          echo "    # openstack group remove user $groupname $query_user_name # POTENTIALLY ABANDONED"
          echo "    # openstack user list --group $groupid # $groupname"
        else
          echo "    # openstack group remove user $groupname $query_user_name"
        fi
        projectids="$(openstack role assignment list -f value -c Project --group "$groupid" | sort | uniq | tr "\n" " ")"
        echo "  group projectids: $projectids"
        groups_projectids+="$projectids"
      done
    fi

    all_projectids=$(echo $query_user_project_id $direct_projectids $groups_projectids | tr " " "\n" | sort | uniq | tr "\n" " ")
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

  done # query_user_id

done # query_pattern
