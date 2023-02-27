#! /bin/bash

for query_project in $@ ; do
  query_project_info=($(openstack project show -f value -c id -c name $query_project))
  query_project_id="${query_project_info[0]}"
  query_project_name="${query_project_info[1]}"
  echo "# Project $query_project_name ($query_project_id)"

  conns_json="$( openstack vpn ipsec site connection list --long -f json | jq '.[] | select(.Project == "'"$query_project_id"'")' )"
  service_ids=($( echo "$conns_json" | jq -r '."VPN Service"' | sort | uniq ))
  for service_id in "${service_ids[@]}" ; do
    service_json="$( openstack vpn service show -f json $service_id )"
    service_name="$( echo "$service_json" | jq -r '.Name' )"
    service_ip="$( echo "$service_json" | jq -r '.external_v4_ip' )"
    echo "openstack vpn ipsec service show $service_id # '$service_name' <- ${service_ip}"

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
      echo " openstack vpn ipsec site connection show $conn_id # '$conn_name' ${service_ip} -> ${conn_peer_address}"
  
      ike_json="$( openstack vpn ike policy show -f json $conn_ike_policy )"
      ike_name="$( echo "$ike_json" | jq -r '.Name' )"
      echo "  openstack vpn ike policy show $conn_ike_policy # '$ike_name'"
  
      ipsec_json="$( openstack vpn ipsec policy show -f json $conn_ipsec_policy )"
      ipsec_name="$( echo "$ipsec_json" | jq -r '.Name' )"
      echo "  openstack vpn ipsec policy show $conn_ipsec_policy # '$ipsec_name'"
  
      local_endpoint_group_json="$( openstack vpn endpoint group show -f json $conn_local_endpoint_group_id )"
      local_endpoint_group_name="$( echo "$local_endpoint_group_json" | jq -r '.Name' )"
      local_endpoint_group_endpoints="$( echo "$local_endpoint_group_json" | jq -r '.Endpoints' )"
      local_subnet_ids=($( echo "$local_endpoint_group_endpoints" | jq -r '.[]' ))
      local_networks=()
      for subnet_id in "${local_subnet_ids[@]}" ; do
        subnet_json="$( openstack subnet show -f json $subnet_id )"
        subnet_name="$( echo "$subnet_json" | jq -r '.name' )"
        subnet_cidr="$( echo "$subnet_json" | jq -r '.cidr' )"
        echo "   openstack subnet show $subnet_id # '$subnet_name' $subnet_cidr"
        local_networks+=($subnet_cidr)
      done
      echo "  openstack vpn endpoint group show $conn_local_endpoint_group_id # '$local_endpoint_group_name' <- ${local_networks[@]}"
  
      peer_endpoint_group_json="$( openstack vpn endpoint group show -f json $conn_peer_endpoint_group_id )"
      peer_endpoint_group_name="$( echo "$peer_endpoint_group_json" | jq -r '.Name' )"
      peer_endpoint_group_endpoints="$( echo "$peer_endpoint_group_json" | jq -r '.Endpoints' )"
      peer_networks=($( echo "$peer_endpoint_group_endpoints" | jq -r '.[]' ))
      echo "  openstack vpn endpoint group show $conn_peer_endpoint_group_id # '$peer_endpoint_group_name' -> ${peer_networks[@]}"
    done
  done
done

