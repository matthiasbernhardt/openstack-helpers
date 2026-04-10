#! /usr/bin/env bash
#
# 2018…2026 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# show all users with direct or indirect relation to a (list of) given project(s)

if [ $BASH_VERSINFO -lt 4 ] ; then
  echo "panic: this script needs bash 4.x with support of associative arrays"
  exit 1
fi

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

for query_pattern in "$@" ; do
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

    userids="$(openstack role assignment list -f value -c User -c Role --project "$query_project_id" | awk  '$1=="'"${roleid_operator}"'" || $1=="'"${roleid_viewer}"'" { print $2 }'| sort | uniq | tr "\n" " " )"
    echo "userids: $userids"
    groupids="$(openstack role assignment list -f value -c Group -c Role --project "$query_project_id" | awk  '$1=="'"${roleid_operator}"'" || $1=="'"${roleid_viewer}"'" { print $2 }' | sort | uniq | tr "\n" " ")"
    echo "groupids: $groupids"
    if [ -n "$groupids" ] ; then
      for groupid in $groupids ; do
        groupname="$(openstack group show -f value -c name $groupid)"
        echo "group: $groupname ($groupid)"
        openstack user list --group $groupid
      done
    fi

    echo '```'
  done
done

