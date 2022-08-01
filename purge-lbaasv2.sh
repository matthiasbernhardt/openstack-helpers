#! /bin/bash

if [[ "$1" == "-p" ]] ; then
  shift
  projects=("$@")
  for project in ${projects[@]} ; do
    project_json="$(openstack project show -f json $project)"
    project_id="$(echo "$project_json" | jq -r ".id")"
    project_name="$(echo "$project_json" | jq -r ".name")"
    loadbalancer_list="$(neutron lbaas-loadbalancer-list -f json 2>/dev/null)"
    loadbalancer_ids=($(echo "$loadbalancer_list" | jq -r '.[] | select(.tenant_id == "'"$project_id"'") | .id' ))
  done
else
  loadbalancer_ids=("$@")
fi

for loadbalancer_id in ${loadbalancer_ids[@]} ; do
  loadbalancer_json="$(neutron lbaas-loadbalancer-show -f json $loadbalancer_id 2>/dev/null)"
  loadbalancer_name="$(echo "$loadbalancer_json" | jq -r '.name' )"
  loadbalancer_project_id="$(echo "$loadbalancer_json" | jq -r '.tenant_id' )"
  echo "# loadbalancer '$loadbalancer_name' (id: $loadbalancer_id, project: $loadbalancer_project_id)"
  loadbalancer_listeners="$(echo "$loadbalancer_json" | jq -r '.listeners' )"
  loadbalancer_listener_ids=($(echo "$loadbalancer_listeners" | jq -r '.[].id' ))
  for listener_id in ${loadbalancer_listener_ids[@]} ; do
    echo "neutron lbaas-listener-delete $listener_id"
  done
  loadbalancer_pools="$(echo "$loadbalancer_json" | jq -r '.pools' )"
  loadbalancer_pool_ids=($(echo "$loadbalancer_pools" | jq -r '.[].id' ))
  for pool_id in ${loadbalancer_pool_ids[@]} ; do
    pool_json="$(neutron lbaas-pool-show -f json $pool_id 2>/dev/null)"
    pool_healthmonitor_id=$(echo "$pool_json" | jq -r '.healthmonitor_id')
    if [ -n "$pool_healthmonitor_id" ] ; then
      echo "neutron lbaas-healthmonitor-delete $pool_healthmonitor_id"
    fi
    echo "neutron lbaas-pool-delete $pool_id"
  done
  echo "neutron lbaas-loadbalancer-delete $loadbalancer_id"
done

