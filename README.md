## Intro

In reference to https://github.com/kubernetes/ingress-nginx/issues/9222 

This is to provide an environment which can be spun up to test changes in
which we can attempt to identify the root cause of the issue referenced.

## Usage

Bring up a kind cluster with the config file defined.

### Cluster & Service Provisioning

```
kind create cluster --config=kind/cluster-config.yaml
```

Using Helmfile, we'll deploy cilium, nginx and an app which uses auth-url.

```
helmfile --kube-context kind-nginx-coredns -f cluster-addons/helmfile.yaml apply
```

### Testing

There's a script that walks through the sequence of steps to illustrate the issue,
and also the nginx reload to rectify.

```
bash test-ingress.sh
Testing endpoint before coredns restart..
Attempt: 1 Status Code: 200
Attempt: 2 Status Code: 200
Attempt: 3 Status Code: 200
Attempt: 4 Status Code: 200
Attempt: 5 Status Code: 200
Attempt: 6 Status Code: 200
Attempt: 7 Status Code: 200
Attempt: 8 Status Code: 200
Attempt: 9 Status Code: 200
Attempt: 10 Status Code: 200
deployment.apps/coredns restarted
Waiting for deployment "coredns" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "coredns" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "coredns" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "coredns" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "coredns" rollout to finish: 1 of 2 updated replicas are available...
deployment "coredns" successfully rolled out
Testing endpoint after coredns restart..
Attempt: 1 Status Code: 200
Attempt: 2 Status Code: 200
Attempt: 3 Status Code: 200
Attempt: 4 Status Code: 200
Attempt: 5 Status Code: 200
Attempt: 6 Status Code: 500         <-- We start to see "Internal Server Error" which is generally consistent in all attempts.
Attempt: 7 Status Code: 500
Attempt: 8 Status Code: 500
Attempt: 9 Status Code: 200
Attempt: 10 Status Code: 500
Reloading NGINX config
2023/07/26 03:29:37 [warn] 444#444: the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
nginx: [warn] the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
2023/07/26 03:29:37 [warn] 444#444: the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
nginx: [warn] the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
2023/07/26 03:29:37 [warn] 444#444: the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
nginx: [warn] the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
2023/07/26 03:29:37 [notice] 444#444: signal process started
Testing endpoint after NGINX reload..
Attempt: 1 Status Code: 500
Attempt: 2 Status Code: 200
Attempt: 3 Status Code: 200
Attempt: 4 Status Code: 200
Attempt: 5 Status Code: 200
Attempt: 6 Status Code: 200
Attempt: 7 Status Code: 200
Attempt: 8 Status Code: 200
Attempt: 9 Status Code: 200
Attempt: 10 Status Code: 200
```

## Monitoring Cilium

Let's use [tmux-exec](https://github.com/predatorray/kubectl-tmux-exec) to get into
each Cilium pod to monitor what's going on throughout the restart of CoreDNS. (Yes i know we could use Hubble)

```
kubectl tmux-exec -n cilium-system -l k8s-app=cilium -- cilium monitor --type drop
```

Let's start of a series of curl requests.

```
while true; do curl http://int-auth.nip.io --resolve 'int-auth.nip.io:80:127.0.0.1' -s -o /dev/null -w "%{http_code}"; echo "\n"; sleep 2;  done
```

Before we restart CoreDNS to reproduce, let's check the current IP's of CoreDNS

```
kubectl --context kind-nginx-coredns -n kube-system get pods -o wide -l k8s-app=kube-dns --no-headers
coredns-6bd9dcdcc7-66z9r   1/1   Running   0     5m13s   10.242.2.84    nginx-coredns-worker2   <none>   <none>
coredns-6bd9dcdcc7-fg5bz   1/1   Running   0     5m13s   10.242.1.170   nginx-coredns-worker    <none>   <none>
```

Now, let's restart CoreDNS.. We should start seeing 500's return from our curl earlier.

```
kubectl --context kind-nginx-coredns -n kube-system rollout restart deployment coredns
deployment.apps/coredns restarted
```
The pods now have new IP's.

```
kubectl --context kind-nginx-coredns -n kube-system get pods -o wide -l k8s-app=kube-dns --no-headers
coredns-d9585599f-f9pxs   1/1   Running   0     10s   10.242.1.44   nginx-coredns-worker    <none>   <none>
coredns-d9585599f-z7k8m   1/1   Running   0     10s   10.242.2.87   nginx-coredns-worker2   <none>   <none>
```

We now see output as per below from cilium monitor. Note that the IP being referenced for the CoreDNS pod is the old pod
ip prior to the restart. 

```
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Unsupported L3 protocol) flow 0x0 to endpoint 0, , identity 37216->unknown: fe80::c85a:63ff:fe03:5b66 -> ff02::2 RouterSolicitation
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
xx drop (Stale or unroutable IP) flow 0x29e44ff to endpoint 0, , identity 10977->unknown: 10.242.0.36:46958 -> 10.242.1.170:53 udp
```

Now, reload nginx or restart the nginx pod, and it no longer references the stale IP. 

### Cleanup 
```
kind cluster delete -n nginx-coredns
```
