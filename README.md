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

### Cleanup 
```
kind cluster delete -n nginx-coredns
```