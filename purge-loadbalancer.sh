#! /bin/bash

#projectid=$1
#loadbalancers=$(openstack loadbalancer list -f value -c id --project $projectid)

loadbalancers=$*
for loadbalancer in $loadbalancers ; do
  echo "# loadbalancer $loadbalancer (the short way)"
  echo "openstack localbalancer delete --cascade $loadbalancer" # should do the trick"
  echo "# loadbalancer $loadbalancer (the long way)"
  status="$(openstack loadbalancer status show $loadbalancer 2>/dev/null)"
  listeners=$(echo "$status" | jq -r '.loadbalancer.listeners[].id')
  for listener in $listeners ; do
    echo "openstack loadbalancer listener delete $listener"
  done
  healthmonitors=$(echo "$status" | jq -r '.loadbalancer.listeners[].pools[].health_monitor.id')
  for healthmonitor in $healthmonitors ; do
    echo "#openstack loadbalancer healthmonitor delete $healthmonitor # cascaded by pool delete!"
  done
  members=$(echo "$status" | jq -r '.loadbalancer.listeners[].pools[].members[].id')
  for member in $members ; do
    echo "#openstack loadbalancer member delete $member # cascaded by pool delete?"
  done
  pools=$(echo "$status" | jq -r '.loadbalancer.listeners[].pools[].id')
  for pool in $pools ; do
    echo "openstack loadbalancer pool delete $pool"
  done
  echo "openstack loadbalancer delete $loadbalancer"
done

