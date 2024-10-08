#! /bin/bash

case "$1" in "-v"|"-d" ) debug="y" ; shift ;; "-q" ) debug="n" ; shift ;; esac
#if [ -z "$debug" ] ; then if tty -s ; then debug="y" ; fi ; fi
dcat() { if [ "$debug" != "y" ] ; then cat > /dev/null ; else cat ; fi ; }
icat() { if [ "$debug" == "n" ] ; then cat > /dev/null ; else cat ; fi ; }
decho() { echo "$@" | dcat ; }
iecho() { echo "$@" | icat ; }
dexec() { decho "$@" > /dev/stderr ; "$@" ; }
dsexec() { decho "$@" > /dev/stderr ; "$@" 2> /dev/null ; }

basename="$(basename "$0")"
query_projects=("$@")
#query_regions=($(openstack region list -f value -c Region | grep -v infra))
query_regions=(cbk dbl fes)


for query_project in ${query_projects[@]} ; do
  query_project_info=($(openstack project show -f value -c id -c name $query_project))
  query_project_id="${query_project_info[0]}"
  query_project_name="${query_project_info[1]}"
  echo "# Project $query_project_name ($query_project_id)"

  if [ -z "$query_project_id" ] ; then continue ; fi

  conns_json="$( dexec openstack vpn ipsec site connection list --long -f json | dexec jq '.[] | select(.Project == "'"$query_project_id"'")' )"
  service_ids=($( echo "$conns_json" | jq -r '."VPN Service"' | sort | uniq ))
  for service_id in "${service_ids[@]}" ; do
    service_json="$( dexec openstack vpn service show -f json $service_id )"
    service_name="$( echo "$service_json" | jq -r '.Name' )"
    service_ip="$( echo "$service_json" | jq -r '.external_v4_ip' )"
    service_subnet="$( echo "$service_json" | jq -r '.Subnet' )"
    echo "openstack vpn service show $service_id # '$service_name' <- ${service_ip}"

    conn_ids=($( echo "$conns_json" | jq -r 'select(."VPN Service" == "'"$service_id"'" ) | .ID' | sort | uniq ))
    for conn_id in "${conn_ids[@]}" ; do
      conn_json="$( echo "$conns_json" | jq 'select(.ID == "'"$conn_id"'")' )"
      conn_name="$( echo "$conn_json" | jq -r '.Name' )"
      conn_vpn_service="$( echo "$conn_json" | jq -r '."VPN Service"' )"
      conn_ipsec_policy="$( echo "$conn_json" | jq -r '."IPSec Policy"' )"
      conn_ike_policy="$( echo "$conn_json" | jq -r '."IKE Policy"' )"
      conn_peer_endpoint_group_id="$( echo "$conn_json" | jq -r '."Peer Endpoint Group ID"' )"
      conn_local_endpoint_group_id="$( echo "$conn_json" | jq -r '."Local Endpoint Group ID"' )"
      conn_peer_address="$( echo "$conn_json" | jq -r '."Peer Address"' )"
      conn_peer_id="$( echo "$conn_json" | jq -r '."Peer ID"' )"
      conn_peer_cidrs="$( echo "$conn_json" | jq -r '."Peer CIDRs"' )"
      echo " openstack vpn ipsec site connection show $conn_id # '$conn_name' ${service_ip} -> ${conn_peer_address}"
  
      ike_json="$( dexec openstack vpn ike policy show -f json $conn_ike_policy )"
      ike_name="$( echo "$ike_json" | jq -r '.Name' )"
      echo "  openstack vpn ike policy show $conn_ike_policy # '$ike_name'"
  
      ipsec_json="$( dexec openstack vpn ipsec policy show -f json $conn_ipsec_policy )"
      ipsec_name="$( echo "$ipsec_json" | jq -r '.Name' )"
      echo "  openstack vpn ipsec policy show $conn_ipsec_policy # '$ipsec_name'"
 
      if [ -n "$conn_local_endpoint_group_id" -a "$conn_local_endpoint_group_id" != "null" ] ; then
        local_endpoint_group_json="$( dexec openstack vpn endpoint group show -f json $conn_local_endpoint_group_id )"
        local_endpoint_group_name="$( echo "$local_endpoint_group_json" | jq -r '.Name' )"
        local_endpoint_group_endpoints="$( echo "$local_endpoint_group_json" | jq -r '.Endpoints' )"
        local_subnet_ids=($( echo "$local_endpoint_group_endpoints" | jq -r '.[]' ))
      else
        local_endpoint_group_name="service: Subnet"
        local_subnet_ids=$service_subnet
      fi
      local_networks=()
      for subnet_id in "${local_subnet_ids[@]}" ; do
        subnet_json="$( dexec openstack subnet show -f json $subnet_id )"
        subnet_name="$( echo "$subnet_json" | jq -r '.name' )"
        subnet_cidr="$( echo "$subnet_json" | jq -r '.cidr' )"
        echo "   openstack subnet show $subnet_id # '$subnet_name' $subnet_cidr"
        local_networks+=($subnet_cidr)
      done
      local_networks=($(echo ${local_networks[@]} | xargs -n 1 | sort -V))
      echo "  openstack vpn endpoint group show $conn_local_endpoint_group_id # '$local_endpoint_group_name' <- ${local_networks[@]}"
  
      if [ -n "$conn_peer_endpoint_group_id" -a "$conn_peer_endpoint_group_id" != "null" ] ; then
        peer_endpoint_group_json="$( dexec openstack vpn endpoint group show -f json $conn_peer_endpoint_group_id )"
        peer_endpoint_group_name="$( echo "$peer_endpoint_group_json" | jq -r '.Name' )"
        peer_endpoint_group_endpoints="$( echo "$peer_endpoint_group_json" | jq -r '.Endpoints' )"
      else
        peer_endpoint_group_name="connection: Peer CIDRs"
        peer_endpoint_group_endpoints="$conn_peer_cidrs"
      fi
      peer_networks=($( echo "$peer_endpoint_group_endpoints" | jq -r '.[]' | sort -V))
      echo "  openstack vpn endpoint group show $conn_peer_endpoint_group_id # '$peer_endpoint_group_name' -> ${peer_networks[@]}"
    done
  done
done

