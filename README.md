## Intro

We've been encountering an issue recently whereby certain services were inaccessible
after a cluster upgrade. After digging in a bit further, we were able determine a
common demonitator between them, they all required authentication and therefore their
Ingress resources all contained a very similar configuration snippet. All had the
[External Authentication](https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/annotations.md#external-authentication)
annotations configured, so we decided to dig deeper... 

Upon doing so, we came across [this issue](https://github.com/kubernetes/ingress-nginx/issues/9222)
which aligned very closely to our setup. EKS, Cilium without KubeProxy etc. 

The purpose of this repo, is to document some of our findings to hopefully assist
in identifying the root cause, as well as to provide an environment where we can easily
reproduce the issue and attempt fixes.

## Key Findings Thus Far 

Whilst being able to reproduce the issue and attempting a few changes. The most obvious of
all is:

* When Cilium is configured without kube-proxy and CoreDNS is restarted, NGINX will
  still send DNS requests to the old CoreDNS IP's. If NGINX is reloaded within the pod,
  or the pod is restarted, the new IP's of CoreDNS is used and the auth-url address begins
  to work. 

* When Cilium is configured with kube-proxy in partial mode, we're unable to reproduce
  the issue. CoreDNS can be restarted and the NGINX will use the new IP's without a
  reload/restart required.


## Usage

We have two kind clusters, one which has Cilium configured without kube-proxy, and a second
one where kube-proxy is set to partial. Ofcourse you will need [kind](https://kind.sigs.k8s.io/)
and [Helmfile](https://github.com/helmfile/helmfile) installed to follow along. 

The following components are installed by Helmfile:
 * NGINX
 * Echo Server with auth-url configured
 * Cilium 

**Note** This has not been setup where you can run these similtaneously. 

## Cilium without KubeProxy 

```
❯ kind create cluster --config kind/kind-cilium-bpf.conf
```

Using Helmfile, we'll deploy cilium, nginx and an app which uses auth-url.

```
helmfile --kube-context kind-cilium-bpf -f cluster-addons/helmfile.yaml -e local-bpf apply
```

Wait for Helmfile to finish, check the cluster to ensure all pods have started up. 

### Run the test script

There's a script that walks through the sequence of steps to illustrate the issue,
and also the nginx reload to rectify.

```
./test-ingress.sh
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
Attempt: 9 Status Code: 500
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

### Monitoring Cilium during test script execution

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
kubectl -n kube-system get pods -o wide -l k8s-app=kube-dns --no-headers
coredns-6bd9dcdcc7-66z9r   1/1   Running   0     5m13s   10.242.2.84    nginx-coredns-worker2   <none>   <none>
coredns-6bd9dcdcc7-fg5bz   1/1   Running   0     5m13s   10.242.1.170   nginx-coredns-worker    <none>   <none>
```

Now, let's restart CoreDNS.. We should start seeing 500's return from our curl earlier.

```
kubectl -n kube-system rollout restart deployment coredns
deployment.apps/coredns restarted
```
The pods now have new IP's.

```
kubectl -n kube-system get pods -o wide -l k8s-app=kube-dns --no-headers
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

### Further Troubleshooting

Addtional troubleshooting docs can be found [here](troubleshooting/BPF.md)

### Cleanup 
```
kind delete cluster -n cilium-bpf
```

## Cilium with KubeProxy

Let's create the kind cluster where Cilium uses kube-proxy.

```
kind create cluster --config kind/kind-cilium-kube-proxy.conf
```

Install all the components with Helmfile and ensure all pods are running.
```
helmfile --kube-context kind-cilium-kube-proxy -f cluster-addons/helmfile.yaml -e local-kube-proxy apply
```

### Run the test script

Now that all pods are up and running, run the test script.
```
 ./test-ingress.sh
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
Waiting for deployment "coredns" rollout to finish: 1 out of 2 new replicas have been updated...
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
Attempt: 6 Status Code: 200
Attempt: 7 Status Code: 200
Attempt: 8 Status Code: 200
Attempt: 9 Status Code: 200
Attempt: 10 Status Code: 200
Reloading NGINX config
2023/07/28 05:42:27 [warn] 239#239: the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
nginx: [warn] the "http2_max_field_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:143
2023/07/28 05:42:27 [warn] 239#239: the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
nginx: [warn] the "http2_max_header_size" directive is obsolete, use the "large_client_header_buffers" directive instead in /etc/nginx/nginx.conf:144
2023/07/28 05:42:27 [warn] 239#239: the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
nginx: [warn] the "http2_max_requests" directive is obsolete, use the "keepalive_requests" directive instead in /etc/nginx/nginx.conf:145
2023/07/28 05:42:27 [notice] 239#239: signal process started
Testing endpoint after NGINX reload..
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
```

We can see that NGINX is able resolve the service despite CoreDNS being restarted.

```
kind delete cluster -n cilium-kube-proxy
```