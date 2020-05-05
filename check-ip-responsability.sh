#!/bin/bash
#
# 2020-02 m.bernhardt@syseleven.de
#
# https://netbox.syseleven.net/ipam/prefixes/?q=&role=cloudgw-pool
#
# 185.56.128.0/22   - 185.56.129.255/22  cbk
# 185.56.132.0/22   - 185.56.133.255/22  cbk
# 195.192.128.0/21  - 195.192.131.255/21 dbl
# 185.46.136.192/26 - 185.46.136.255/26  ybk
# 151.252.44.64/26  - 151.252.44.127/26  zbk
#
# echo "https://netbox.syseleven.net/ipam/prefixes/?q=$(echo $ip | sed -e 's/:/%3A/g')"
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
query_regions=(cbk dbl)

for fip in "${query_fips[@]}" ; do

  for try_region in "${query_regions[@]}" ; do
    port_id=$(dsexec openstack --os-region "$try_region" floating ip show -f value -c port_id "$fip" )
    decho "port_id:$port_id"
    if [ -n "$port_id" ] ; then
      region="$try_region"
      iecho "$fip found in $region"
      break
    fi
  done

  if [ -z "$port_id" ] ; then
    iecho "$fip not found in any region -> https://netbox.syseleven.net/ipam/prefixes/?q=$(echo $fip | sed -e 's/:/%3A/g')"
    break
  fi

  port_show=($(dexec openstack --os-region $region port show -f value -c device_id -c device_owner -c project_id "$port_id"))
  decho "${port_show[*]}"
  port_device_id="${port_show[0]}"
  decho "port_device_id:$port_device_id"
  port_device_owner="${port_show[1]}"
  decho "port_device_owner:$port_device_owner"
  port_project_id="${port_show[2]}"
  decho "port_project_id:$port_project_id"

  case "$port_device_owner" in
    compute:*)
      server_show=($(dexec openstack --os-region $region server show -f value -c name -c project_id "$port_device_id"))
      decho "${server_show[*]}"
      server_name="${server_show[0]}"
      decho "server_name:$server_name"
      server_project_id="${server_show[1]}"
      decho "server_project_id:$server_project_id"
      iecho "server $port_device_id $server_name"
      project_id=$server_project_id
      ;;
    neutron:LOADBALANCERV2)
      iecho "lbaasv2 $port_device_id"
      project_id=$port_project_id
      ;;
    *)
      iecho "clueless about $port_device_owner"
      project_id=$port_project_id
  esac

  project_name="$(dexec openstack project show -f value -c name "$project_id")"
  decho "project_id:$project_id"
  decho "project_name:$project_name"
  echo "$project_name $project_id"

done

