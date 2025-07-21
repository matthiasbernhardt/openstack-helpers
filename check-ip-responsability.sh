#!/bin/bash
#
# 2020…2025 M.Bernhardt, SysEleven GmbH, Berlin, Germany
#
# find resources related to a floating ip address
#

case "$1" in "-v"|"-d" ) debug="y" ; shift ;; "-q" ) debug="n" ; shift ;; esac
#if [ -z "$debug" ] ; then if tty -s ; then debug="y" ; fi ; fi
dcat() { if [ "$debug" != "y" ] ; then cat > /dev/null ; else cat ; fi ; }
icat() { if [ "$debug" == "n" ] ; then cat > /dev/null ; else cat ; fi ; }
decho() { echo "$@" | dcat ; }
iecho() { echo "$@" | icat ; }
dexec() { decho "$@" > /dev/stderr ; "$@" ; }
dsexec() { decho "$@" > /dev/stderr ; "$@" 2> /dev/null ; }

basename="$(basename "$0")"
query_fips=("$@")
query_regions=(cbk dbl fes ham1 dus2)

for fip in "${query_fips[@]}" ; do

  decho "looking for $fip"

  if [ -x "$(type -p fip2region.sh)" ] ; then
    cache_region=$(fip2region.sh "$fip")
  else
    unset cache_region
  fi
  if [ -n "$cache_region" ] ; then
    iecho "$fip assumed in $cache_region"
  else
    decho "$fip not in a cached region"
  fi

  try_regions=($cache_region $(echo "${query_regions[@]}" | tr " " "\n" | grep -v -e "${cache_region:=notfound}"))
  decho "query_regions:${query_regions[*]} cache_region:$cache_region -> try_regions:${try_regions[*]}"
  for try_region in "${try_regions[@]}" ; do
    port_id=$(dsexec openstack --os-region "$try_region" floating ip show -f value -c port_id "$fip" )
    decho "port_id:$port_id (fip)"
    if [ -n "$port_id" ] ; then
      region="$try_region"
      iecho "$fip found by fip in $region"
      break
    fi
    port_id=$(dsexec openstack --os-region "$try_region" port list --fixed-ip 'ip-address='"$fip" -f value -c ID )
    decho "port_id:$port_id (port)"
    if [ -n "$port_id" ] ; then
      region="$try_region"
      iecho "$fip found by port in $region"
      break
    fi
  done

  if [ -z "$port_id" ] ; then
    iecho "$fip not found in any region"
    continue
  fi

  port_json="$(dexec openstack --os-region $region port show -f json "$port_id")"
  port_device_id="$(echo "$port_json" | jq -r ".device_id")"
  decho "port_device_id:$port_device_id"
  port_device_owner="$(echo "$port_json" | jq -r ".device_owner")"
  decho "port_device_owner:$port_device_owner"
  port_project_id="$(echo "$port_json" | jq -r ".project_id")"
  decho "port_project_id:$port_project_id"

  case "$port_device_owner" in
    compute:*)
      server_json="$(dexec openstack --os-region $region server show -f json "$port_device_id")"
      server_name="$(echo "$server_json" | jq -r ".name")"
      decho "server_name:$server_name"
      server_project_id="$(echo "$server_json" | jq -r ".project_id")"
      decho "server_project_id:$server_project_id"
      iecho "server $port_device_id $server_name"
      project_id=$server_project_id
      ;;
    neutron:LOADBALANCERV2)
      iecho "lbaasv2 $port_device_id"
      project_id=$port_project_id
      ;;
    Octavia)
      iecho "octavia $port_device_id"
      loadbalancer_id="${port_device_id##lb-}"
      loadbalancer_json="$(dexec openstack --os-region $region loadbalancer show -f json "$loadbalancer_id")"
      loadbalancer_name="$(echo "$loadbalancer_json" | jq -r ".name")"
      decho "loadbalancer_name:$loadbalancer_name"
      loadbalancer_project_id="$(echo "$loadbalancer_json" | jq -r ".project_id")"
      decho "loadbalancer_project_id:$loadbalancer_project_id"
      iecho "octavia $loadbalancer_id $loadbalancer_name"
      project_id=$loadbalancer_project_id
      ;;
    network:router_gateway|network:vpn_router_gateway|network:router_interface)
      router_json="$(dexec openstack --os-region $region router show -f json "$port_device_id")"
      router_name="$(echo "$router_json" | jq -r ".name")"
      decho "router_name:$router_name"
      router_project_id="$(echo "$router_json" | jq -r ".project_id")"
      decho "router_project_id:$router_project_id"
      iecho "router $port_device_id $router_name"
      project_id=$router_project_id
      ;;
    *)
      iecho "clueless about device type $port_device_owner"
      project_id=$port_project_id
  esac

  project_json="$(dexec openstack project show -f json $project_id)"
  project_name="$(echo "$project_json" | jq -r ".name")"
  project_parent_id="$(echo "$project_json" | jq -r ".parent_id")"
  project_description="$(echo "$project_json" | jq -r ".description")"

  decho "project_id:$project_id"
  decho "project_name:$project_name"
  echo "project $project_id $project_name"

done

