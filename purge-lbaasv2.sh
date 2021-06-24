#! /bin/bash

#projectid=$1
#loadbalancers=$(neutron lbaas-loadbalancer-list -f value 2>/dev/null | awk '$3 == "'$project'" {print $1}')

loadbalancers=$*
for loadbalancer in $loadbalancers ; do
  echo "# loadbalancer $loadbalancer"
  status="$(neutron lbaas-loadbalancer-status $loadbalancer 2>/dev/null)"
  listeners=$(neutron lbaas-loadbalancer-show -f value -c listeners $loadbalancer 2>/dev/null | sed s+\'+\"+g | jq -r '.[].id' -r)
  for listener in $listeners ; do
    echo "neutron lbaas-listener-delete $listener"
  done
  pools=$(neutron lbaas-loadbalancer-show -f value -c pools $loadbalancer 2>/dev/null | sed s+\'+\"+g | jq -r '.[].id' -r)
  for pool in $pools ; do
    echo "neutron lbaas-pool-delete $pool"
  done
  echo "neutron lbaas-loadbalancer-delete $loadbalancer"
done

