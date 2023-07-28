Let's try obtain some further debug info once restart CoreDNS to see whether we can spot anything..

0. Let's send some curl requests continously to the endpoint.

```
while true; do curl http://int-auth.nip.io --resolve 'int-auth.nip.io:80:127.0.0.1' -s -o /dev/null -w %{http_code}; sleep 2; done
```

1. Let's get the NGINX pod ip and the BPF endpoint

```
kubectl --context kind-nginx-coredns -n nginx get pods -o wide
NAME                                              READY   STATUS    RESTARTS   AGE   IP            NODE                          NOMINATED NODE   READINESS GATES
nginx-ingress-nginx-controller-756467b48c-fsxjb   1/1     Running   0          27h   10.242.1.23   nginx-coredns-control-plane   <none>           <none>
```
```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf endpoint list
IP ADDRESS       LOCAL ENDPOINT INFO
10.242.1.23:0    id=174   flags=0x0000 ifindex=10  mac=32:F9:C5:46:BB:AA nodemac=B6:E1:B6:52:97:1D
```

2. Let's get the CoreDNS IP's.

```
kubectl --context kind-nginx-coredns -n kube-system get pods -o wide -l k8s-app=kube-dns
NAME                      READY   STATUS    RESTARTS   AGE   IP             NODE                    NOMINATED NODE   READINESS GATES
coredns-64897985d-fv859   1/1     Running   0          27h   10.242.0.87    nginx-coredns-worker2   <none>           <none>
coredns-64897985d-gckw8   1/1     Running   0          27h   10.242.0.178   nginx-coredns-worker2   <none>           <none>
```
```
root@nginx-coredns-worker2:/home/cilium# cilium bpf endpoint list
IP ADDRESS       LOCAL ENDPOINT INFO
10.242.0.87:0    id=1020  flags=0x0000 ifindex=24  mac=12:CF:70:69:B4:A5 nodemac=5A:D3:5A:1A:A2:1C
10.242.0.178:0   id=1583  flags=0x0000 ifindex=12  mac=F2:78:5C:6D:DE:3F nodemac=36:C7:3C:43:0A:17 
```

3. Obtain connection tracking info for the Nginx Pod 

We can see the connection tracking for the NGINX pods show comms to the CoreDNS IP's above.

```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP OUT 10.242.1.23:47126 -> 10.242.0.87:53 expires=20944898 RxPackets=24 RxBytes=3864 RxFlagsSeen=0x00 LastRxReport=20944664 TxPackets=24 TxBytes=2184 TxFlagsSeen=0x00 LastTxReport=20944664 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:57512 -> 10.242.0.178:53 expires=20944914 RxPackets=24 RxBytes=3864 RxFlagsSeen=0x00 LastRxReport=20944680 TxPackets=24 TxBytes=2184 TxFlagsSeen=0x00 LastTxReport=20944680 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:58765 -> 10.242.0.178:53 expires=20945009 RxPackets=26 RxBytes=4186 RxFlagsSeen=0x00 LastRxReport=20944775 TxPackets=26 TxBytes=2366 TxFlagsSeen=0x00 LastTxReport=20944775 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:36404 -> 10.242.0.178:53 expires=20945001 RxPackets=26 RxBytes=4186 RxFlagsSeen=0x00 LastRxReport=20944767 TxPackets=26 TxBytes=2366 TxFlagsSeen=0x00 LastTxReport=20944767 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:40186 -> 10.242.0.178:53 expires=20945033 RxPackets=26 RxBytes=4186 RxFlagsSeen=0x00 LastRxReport=20944799 TxPackets=26 TxBytes=2366 TxFlagsSeen=0x00 LastTxReport=20944799 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:42374 -> 10.242.0.178:53 expires=20945065 RxPackets=26 RxBytes=4186 RxFlagsSeen=0x00 LastRxReport=20944831 TxPackets=26 TxBytes=2366 TxFlagsSeen=0x00 LastTxReport=20944831 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```

```
root@nginx-coredns-worker2:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP IN 10.242.1.23:58765 -> 10.242.0.178:53 expires=20945009 RxPackets=26 RxBytes=2366 RxFlagsSeen=0x00 LastRxReport=20944775 TxPackets=26 TxBytes=4186 TxFlagsSeen=0x00 LastTxReport=20944775 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:36404 -> 10.242.0.178:53 expires=20945001 RxPackets=26 RxBytes=2366 RxFlagsSeen=0x00 LastRxReport=20944767 TxPackets=26 TxBytes=4186 TxFlagsSeen=0x00 LastTxReport=20944767 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:57512 -> 10.242.0.178:53 expires=20944914 RxPackets=24 RxBytes=2184 RxFlagsSeen=0x00 LastRxReport=20944680 TxPackets=24 TxBytes=3864 TxFlagsSeen=0x00 LastTxReport=20944680 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:47126 -> 10.242.0.87:53 expires=20944898 RxPackets=24 RxBytes=2184 RxFlagsSeen=0x00 LastRxReport=20944664 TxPackets=24 TxBytes=3864 TxFlagsSeen=0x00 LastTxReport=20944664 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:40186 -> 10.242.0.178:53 expires=20945033 RxPackets=26 RxBytes=2366 RxFlagsSeen=0x00 LastRxReport=20944799 TxPackets=26 TxBytes=4186 TxFlagsSeen=0x00 LastTxReport=20944799 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:42374 -> 10.242.0.178:53 expires=20945065 RxPackets=26 RxBytes=2366 RxFlagsSeen=0x00 LastRxReport=20944831 TxPackets=26 TxBytes=4186 TxFlagsSeen=0x00 LastTxReport=20944831 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```

4. Restart CoreDNS

```
kubectl --context kind-nginx-coredns -n kube-system get pods -o wide -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS   AGE   IP             NODE                          NOMINATED NODE   READINESS GATES
coredns-597b6c9bd8-gbmsq   1/1     Running   0          86s   10.242.1.221   nginx-coredns-control-plane   <none>           <none>
coredns-597b6c9bd8-xpcw4   1/1     Running   0          86s   10.242.2.93    nginx-coredns-worker          <none>           <none>
```
```
kubectl --context kind-nginx-coredns -n kube-system get ciliumendpoints.cilium.io
NAME                       ENDPOINT ID   IDENTITY ID   INGRESS ENFORCEMENT   EGRESS ENFORCEMENT   VISIBILITY POLICY   ENDPOINT STATE   IPV4           IPV6
coredns-597b6c9bd8-gbmsq   1505          19285                                                                        ready            10.242.1.221
coredns-597b6c9bd8-xpcw4   3339          19285                                                                        ready            10.242.2.93
```

5. Check the connection tracking again 

We still see DNS requests going to the old CoreDNS pods 
```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP OUT 10.242.1.23:47126 -> 10.242.0.87:53 expires=20945625 RxPackets=30 RxBytes=4830 RxFlagsSeen=0x00 LastRxReport=20945165 TxPackets=38 TxBytes=3458 TxFlagsSeen=0x00 LastTxReport=20945372 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:57512 -> 10.242.0.178:53 expires=20945471 RxPackets=30 RxBytes=4830 RxFlagsSeen=0x00 LastRxReport=20945237 TxPackets=30 TxBytes=2730 TxFlagsSeen=0x00 LastTxReport=20945237 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:58765 -> 10.242.0.178:53 expires=20945487 RxPackets=32 RxBytes=5152 RxFlagsSeen=0x00 LastRxReport=20945253 TxPackets=32 TxBytes=2912 TxFlagsSeen=0x00 LastTxReport=20945253 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:36404 -> 10.242.0.178:53 expires=20945447 RxPackets=32 RxBytes=5152 RxFlagsSeen=0x00 LastRxReport=20945213 TxPackets=32 TxBytes=2912 TxFlagsSeen=0x00 LastTxReport=20945213 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:40186 -> 10.242.0.178:53 expires=20945455 RxPackets=32 RxBytes=5152 RxFlagsSeen=0x00 LastRxReport=20945221 TxPackets=32 TxBytes=2912 TxFlagsSeen=0x00 LastTxReport=20945221 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:42374 -> 10.242.0.178:53 expires=20945543 RxPackets=32 RxBytes=5152 RxFlagsSeen=0x00 LastRxReport=20945309 TxPackets=32 TxBytes=2912 TxFlagsSeen=0x00 LastTxReport=20945309 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```

```
root@nginx-coredns-worker2:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
root@nginx-coredns-worker2:/home/cilium#
```

6. Let's try flush

Flushing the connection tracking to see if this makes a difference 

```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ct flush global
Flushed 5574 entries from /sys/fs/bpf/tc/globals/cilium_ct4_global
Flushed 2609 entries from /sys/fs/bpf/tc/globals/cilium_ct_any4_global
```

```
root@nginx-coredns-worker:/home/cilium# cilium bpf ct flush global
Flushed 47 entries from /sys/fs/bpf/tc/globals/cilium_ct4_global
Flushed 1885 entries from /sys/fs/bpf/tc/globals/cilium_ct_any4_global
```

```
root@nginx-coredns-worker2:/home/cilium# cilium bpf ct flush global
Flushed 3274 entries from /sys/fs/bpf/tc/globals/cilium_ct4_global
Flushed 1876 entries from /sys/fs/bpf/tc/globals/cilium_ct_any4_global
```

7. Review connection tracking again

Still seeing requests going to the old CoreDNS IP's
```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP OUT 10.242.1.23:47126 -> 10.242.0.87:53 expires=20946415 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=10 TxBytes=910 TxFlagsSeen=0x00 LastTxReport=20946181 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:36404 -> 10.242.0.178:53 expires=20946501 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=8 TxBytes=728 TxFlagsSeen=0x00 LastTxReport=20946267 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```

8. Check BPF IP Cache for CoreDNS IP's

Those can be found fine.

```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ipcache list | egrep '(10.242.0.87|10.242.0.178)'
root@nginx-coredns-control-plane:/home/cilium#
```
```
root@nginx-coredns-worker:/home/cilium# cilium bpf ipcache list | egrep '(10.242.0.87|10.242.0.178)'
root@nginx-coredns-worker:/home/cilium#
```
```
root@nginx-coredns-worker2:/home/cilium# cilium bpf ipcache list | egrep '(10.242.2.126|10.242.0.109)'
10.242.0.109/32     1 0 0.0.0.0 0
10.242.2.126/32     6 0 172.19.0.4 8136
```

7. Reload Nginx

```
nginx-ingress-nginx-controller-756467b48c-fsxjb   1/1     Running   0          28h
❯ kubectl --context kind-nginx-coredns -n nginx exec -it nginx-ingress-nginx-controller-756467b48c-fsxjb -- nginx -s reload
2023/07/28 03:28:16 [warn] 240#240: the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
nginx: [warn] the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
2023/07/28 03:28:16 [warn] 240#240: the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
nginx: [warn] the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
2023/07/28 03:28:16 [warn] 240#240: the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
nginx: [warn] the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
2023/07/28 03:28:16 [notice] 240#240: signal process started
```

Once we reload, the connection tracking shows connections appearing the current CoreDNS pod ip's.

```
root@nginx-coredns-control-plane:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP OUT 10.242.1.23:49707 -> 10.242.2.93:53 expires=20948712 RxPackets=4 RxBytes=644 RxFlagsSeen=0x00 LastRxReport=20948478 TxPackets=4 TxBytes=364 TxFlagsSeen=0x00 LastTxReport=20948478 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:58539 -> 10.242.2.93:53 expires=20948752 RxPackets=4 RxBytes=644 RxFlagsSeen=0x00 LastRxReport=20948518 TxPackets=4 TxBytes=364 TxFlagsSeen=0x00 LastTxReport=20948518 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:47126 -> 10.242.0.87:53 expires=20948166 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=34 TxBytes=3094 TxFlagsSeen=0x00 LastTxReport=20947913 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:57512 -> 10.242.0.178:53 expires=20948291 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=60 TxBytes=5460 TxFlagsSeen=0x00 LastTxReport=20948038 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:58765 -> 10.242.0.178:53 expires=20948542 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=36 TxBytes=3276 TxFlagsSeen=0x00 LastTxReport=20948308 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:36404 -> 10.242.0.178:53 expires=20946540 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=12 TxBytes=1092 TxFlagsSeen=0x00 LastTxReport=20946306 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:40186 -> 10.242.0.178:53 expires=20947791 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=24 TxBytes=2184 TxFlagsSeen=0x00 LastTxReport=20947538 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:42374 -> 10.242.0.178:53 expires=20948417 RxPackets=0 RxBytes=0 RxFlagsSeen=0x00 LastRxReport=0 TxPackets=48 TxBytes=4368 TxFlagsSeen=0x00 LastTxReport=20948183 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:53084 -> 10.242.1.221:53 expires=20948657 RxPackets=2 RxBytes=182 RxFlagsSeen=0x00 LastRxReport=20948423 TxPackets=2 TxBytes=322 TxFlagsSeen=0x00 LastTxReport=20948423 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:38628 -> 10.242.1.221:53 expires=20948736 RxPackets=4 RxBytes=364 RxFlagsSeen=0x00 LastRxReport=20948502 TxPackets=4 TxBytes=644 TxFlagsSeen=0x00 LastTxReport=20948502 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:38628 -> 10.242.1.221:53 expires=20948736 RxPackets=4 RxBytes=644 RxFlagsSeen=0x00 LastRxReport=20948502 TxPackets=4 TxBytes=364 TxFlagsSeen=0x00 LastTxReport=20948502 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:53084 -> 10.242.1.221:53 expires=20948657 RxPackets=2 RxBytes=322 RxFlagsSeen=0x00 LastRxReport=20948423 TxPackets=2 TxBytes=182 TxFlagsSeen=0x00 LastTxReport=20948423 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:52855 -> 10.242.1.221:53 expires=20948720 RxPackets=2 RxBytes=182 RxFlagsSeen=0x00 LastRxReport=20948486 TxPackets=2 TxBytes=322 TxFlagsSeen=0x00 LastTxReport=20948486 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:52855 -> 10.242.1.221:53 expires=20948720 RxPackets=2 RxBytes=322 RxFlagsSeen=0x00 LastRxReport=20948486 TxPackets=2 TxBytes=182 TxFlagsSeen=0x00 LastTxReport=20948486 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP OUT 10.242.1.23:53827 -> 10.242.2.93:53 expires=20948633 RxPackets=2 RxBytes=322 RxFlagsSeen=0x00 LastRxReport=20948399 TxPackets=2 TxBytes=182 TxFlagsSeen=0x00 LastTxReport=20948399 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```

```
root@nginx-coredns-worker:/home/cilium# cilium bpf ct list global -D | grep 10.242.1.23  | grep ":53" | grep -v TCP
UDP IN 10.242.1.23:53827 -> 10.242.2.93:53 expires=20948633 RxPackets=2 RxBytes=182 RxFlagsSeen=0x00 LastRxReport=20948399 TxPackets=2 TxBytes=322 TxFlagsSeen=0x00 LastTxReport=20948399 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:49707 -> 10.242.2.93:53 expires=20948712 RxPackets=4 RxBytes=364 RxFlagsSeen=0x00 LastRxReport=20948478 TxPackets=4 TxBytes=644 TxFlagsSeen=0x00 LastTxReport=20948478 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
UDP IN 10.242.1.23:58539 -> 10.242.2.93:53 expires=20948752 RxPackets=4 RxBytes=364 RxFlagsSeen=0x00 LastRxReport=20948518 TxPackets=4 TxBytes=644 TxFlagsSeen=0x00 LastTxReport=20948518 Flags=0x0000 [ ] RevNAT=0 SourceSecurityID=35631 IfIndex=0
```
