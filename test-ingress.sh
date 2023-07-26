#!/bin/bash

echo "Testing endpoint before coredns restart.."
for i in `seq 10`
do
  STATUS_CODE=$(curl http://int-auth.nip.io --resolve 'int-auth.nip.io:80:127.0.0.1' -s -o /dev/null -w %{http_code})
  echo "Attempt:" $i "Status Code:" "${STATUS_CODE}"
  sleep 2
done
  

kubectl --context kind-nginx-coredns -n kube-system rollout restart deployment coredns
kubectl --context kind-nginx-coredns -n kube-system rollout status deployment coredns

echo "Testing endpoint after coredns restart.."
for i in `seq 10`
do
  STATUS_CODE=$(curl http://int-auth.nip.io --resolve 'int-auth.nip.io:80:127.0.0.1' -s -o /dev/null -w %{http_code})
  echo "Attempt:" $i "Status Code:" "${STATUS_CODE}"
  sleep 2
done

echo "Reloading NGINX config"
CONTROLLER_POD=$(kubectl --context kind-nginx-coredns -n nginx get pods --no-headers | awk '{print $1}')
kubectl --context kind-nginx-coredns -n nginx exec -it "${CONTROLLER_POD}" -- nginx -s reload

echo "Testing endpoint after NGINX reload.."
for i in `seq 10`
do
  STATUS_CODE=$(curl http://int-auth.nip.io --resolve 'int-auth.nip.io:80:127.0.0.1' -s -o /dev/null -w %{http_code})
  echo "Attempt:" $i "Status Code:" "${STATUS_CODE}"
  sleep 2
done

