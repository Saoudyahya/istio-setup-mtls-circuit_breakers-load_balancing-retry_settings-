# Istio Traffic Management Guide

![Istio Logo](https://istio.io/latest/img/logo.svg)

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Setup Guide](#setup-guide)
5. [Load Balancing Demo](#load-balancing-demo)
6. [Circuit Breaker Demo](#circuit-breaker-demo)
7. [Monitoring & Verification](#monitoring--verification)
8. [Cleanup](#cleanup)
9. [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

This repository demonstrates two critical Istio traffic management patterns:

- **Load Balancing**: Distribution of traffic across multiple service instances using Round Robin strategy
- **Circuit Breaker**: Resilience pattern to prevent cascading failures through connection pooling and outlier detection

### Technologies Used

| Technology | Purpose |
|------------|---------|
| ![Kubernetes](https://kubernetes.io/images/kubernetes-horizontal-color.png) | Container orchestration platform |
| ![Istio](https://istio.io/latest/img/logo.svg) | Service mesh for traffic management |
| Fortio | Load testing tool |
| HTTPBin | HTTP testing service |

---

## ✅ Prerequisites

Before starting, ensure you have:

- Kubernetes cluster (v1.20+)
- Istio installed (v1.16+)
- kubectl configured
- Istio sidecar injection enabled in your namespace

```bash
# Enable Istio injection for default namespace
kubectl label namespace default istio-injection=enabled

# Verify Istio installation
kubectl get pods -n istio-system
```

---

## 🏗️ Architecture

### Load Balancing Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Fortio Client                        │
│                   (Load Generator)                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ HTTP Requests
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Istio Virtual Service                       │
│           (Round Robin Load Balancer)                    │
└─────┬──────────────┬──────────────┬─────────────────────┘
      │              │              │
      ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│HTTPBin v1│  │HTTPBin v1│  │HTTPBin v2│  │HTTPBin v2│
│ Pod 1    │  │ Pod 2    │  │ Pod 1    │  │ Pod 2    │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### Circuit Breaker Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Fortio Client                        │
│              (Concurrent Requests: 20)                   │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Circuit Breaker Rules                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Connection Pool:                                  │  │
│  │  - Max Connections: 10                           │  │
│  │  - Max Pending Requests: 10                      │  │
│  │  - Max Requests Per Connection: 2                │  │
│  │                                                   │  │
│  │ Outlier Detection:                               │  │
│  │  - Consecutive 5xx Errors: 3                     │  │
│  │  - Ejection Time: 30s                            │  │
│  │  - Interval: 30s                                 │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
      ┌──────────────┼──────────────┐
      ▼              ▼              ▼
  ✅ Allowed    ❌ Rejected    🔄 Retry
  (10 conn)    (Overflow)    (Failed)
      │
      ▼
┌──────────┐
│ HTTPBin  │
│ Service  │
└──────────┘
```

---

## 🚀 Setup Guide

### Step 1: Deploy Base Services

Deploy HTTPBin service and Fortio load testing client:

```bash
# Navigate to circuit breaker directory
cd cb/

# Deploy services
kubectl apply -f Deployment.yaml

# Verify deployment
kubectl get pods
kubectl get svc
```

**Expected Output:**
```
NAME                       READY   STATUS    RESTARTS   AGE
fortio-xxxxx              2/2     Running   0          1m
httpbin-xxxxx             2/2     Running   0          1m
```

### Step 2: Wait for Pods to be Ready

```bash
# Watch pod status
kubectl get pods -w

# Check if Istio sidecars are injected
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

You should see both the main container and `istio-proxy` for each pod.

---

## 🔄 Load Balancing Demo

### Step 1: Deploy Multiple Versions

```bash
cd ../lbs/

# Deploy v1 and v2 with 2 replicas each
kubectl apply -f httpbin-v1.yaml

# Verify 4 pods are running (2x v1, 2x v2)
kubectl get pods -l app=httpbin
```

### Step 2: Apply Round Robin Load Balancing

```bash
# Apply destination rule
kubectl apply -f lb-round-robin.yaml

# Verify destination rule
kubectl get destinationrule httpbin-lb-round-robin -o yaml
```

### Step 3: Generate Load

```bash
# Get Fortio pod name
export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}')

# Send 100 requests
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load \
  -c 1 -qps 0 -n 100 -loglevel Warning \
  http://httpbin:8000/get
```

### Step 4: Verify Distribution

Use the provided PowerShell script to check request distribution:

```powershell
# Run the monitoring script
./LB-ROUND-ROBIN.sh
```

**Expected Result:**
Each pod should receive approximately 25% of requests (25 out of 100).

```
--- Pod: httpbin-v1-xxxx ---
Pod IP: 10.244.0.15
Requests received: 25

--- Pod: httpbin-v1-yyyy ---
Pod IP: 10.244.0.16
Requests received: 25

--- Pod: httpbin-v2-xxxx ---
Pod IP: 10.244.0.17
Requests received: 25

--- Pod: httpbin-v2-yyyy ---
Pod IP: 10.244.0.18
Requests received: 25
```

### Load Balancing Flow Diagram

```
Request Flow (Round Robin):

Request 1  ──────────────────────> HTTPBin v1 Pod 1
Request 2  ──────────────────────> HTTPBin v1 Pod 2
Request 3  ──────────────────────> HTTPBin v2 Pod 1
Request 4  ──────────────────────> HTTPBin v2 Pod 2
Request 5  ──────────────────────> HTTPBin v1 Pod 1 (cycle repeats)
```

---

## 🛡️ Circuit Breaker Demo

### Step 1: Apply Circuit Breaker Rules

```bash
cd ../cb/

# Apply destination rule with circuit breaker
kubectl apply -f DestinationRuleCB.yaml

# Verify the rule
kubectl describe destinationrule httpbin-circuit-breaker
```

### Step 2: Test Normal Behavior

```bash
# Single request test
kubectl exec "$FORTIO_POD" -c fortio -- \
  /usr/bin/fortio curl -quiet http://httpbin:8000/get
```

**Expected:** ✅ Request succeeds (200 OK)

### Step 3: Trigger Circuit Breaker

```bash
# Run the test script
bash script.sh
```

This script performs three tests:

#### Test 1: Normal Request
```bash
kubectl exec "$FORTIO_POD" -c fortio -- \
  /usr/bin/fortio curl -quiet http://httpbin:8000/get
```

#### Test 2: Concurrent Connections (Trigger Connection Pool Limit)
```bash
kubectl exec "$FORTIO_POD" -c fortio -- \
  /usr/bin/fortio load -c 20 -qps 0 -n 200 -loglevel Warning \
  http://httpbin:8000/get
```

**Parameters:**
- `-c 20`: 20 concurrent connections (exceeds max of 10)
- `-qps 0`: No rate limiting, send as fast as possible
- `-n 200`: Total 200 requests

#### Test 3: Delayed Responses (Trigger Timeout)
```bash
kubectl exec "$FORTIO_POD" -c fortio -- \
  /usr/bin/fortio load -c 10 -qps 0 -n 100 -loglevel Warning \
  http://httpbin:8000/delay/5
```

### Step 4: Analyze Results

```bash
# Check Istio proxy stats
kubectl exec "$FORTIO_POD" -c istio-proxy -- \
  pilot-agent request GET stats | grep -E 'upstream_rq_pending_overflow|upstream_rq_503'
```

**Key Metrics:**

| Metric | Description | What to Look For |
|--------|-------------|------------------|
| `upstream_rq_pending_overflow` | Requests rejected due to connection pool overflow | Should be > 0 after test |
| `upstream_rq_503` | 503 Service Unavailable responses | Indicates circuit breaker activation |
| `upstream_cx_overflow` | Connection overflow count | Shows connection limit enforcement |

### Circuit Breaker State Diagram

```
                    ┌─────────────┐
                    │   CLOSED    │
                    │  (Normal)   │
                    └──────┬──────┘
                           │
              Errors < 3   │   Errors >= 3
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌─────────┐   ┌─────────┐   ┌─────────┐
        │ CLOSED  │   │  OPEN   │   │  OPEN   │
        └─────────┘   │(Tripped)│   └─────────┘
                      └────┬────┘
                           │
                      30s elapsed
                           │
                           ▼
                    ┌─────────────┐
                    │ HALF-OPEN   │
                    │  (Testing)  │
                    └──────┬──────┘
                           │
              Success      │      Failure
              ┌────────────┼────────────┐
              ▼            │            ▼
        ┌─────────┐        │      ┌─────────┐
        │ CLOSED  │        │      │  OPEN   │
        └─────────┘        │      └─────────┘
```

---

## 📊 Monitoring & Verification

### Check Istio Metrics

```bash
# View circuit breaker metrics
kubectl exec "$FORTIO_POD" -c istio-proxy -- \
  curl -s localhost:15000/stats/prometheus | grep -E 'upstream_rq|upstream_cx'

# Key metrics to monitor:
# - istio_requests_total
# - upstream_rq_pending_overflow
# - upstream_rq_pending_active
# - upstream_cx_active
# - upstream_cx_overflow
```

### Visualize with Kiali (Optional)

```bash
# Port-forward Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Open browser to http://localhost:20001
```

### Grafana Dashboards (Optional)

```bash
# Port-forward Grafana
kubectl port-forward -n istio-system svc/grafana 3000:3000

# Access at http://localhost:3000
# Default credentials: admin/admin
```

---

## 🧹 Cleanup

### Remove Load Balancing Setup

```bash
kubectl delete -f lbs/httpbin-v1.yaml
kubectl delete -f lbs/lb-round-robin.yaml
```

### Remove Circuit Breaker Setup

```bash
kubectl delete -f cb/Deployment.yaml
kubectl delete -f cb/DestinationRuleCB.yaml
```

### Complete Cleanup

```bash
# Delete all resources
kubectl delete deployment httpbin httpbin-v1 httpbin-v2 fortio
kubectl delete service httpbin fortio
kubectl delete destinationrule --all
```

---

## 🔧 Troubleshooting

### Issue: Pods Not Ready

**Symptoms:** Pods stuck in `ContainerCreating` or `CrashLoopBackOff`

**Solutions:**
```bash
# Check pod logs
kubectl logs <pod-name> -c httpbin
kubectl logs <pod-name> -c istio-proxy

# Check events
kubectl describe pod <pod-name>

# Verify Istio injection
kubectl get namespace -L istio-injection
```

### Issue: Istio Sidecar Not Injected

**Symptoms:** Only 1/1 containers ready instead of 2/2

**Solutions:**
```bash
# Enable injection
kubectl label namespace default istio-injection=enabled

# Restart deployments
kubectl rollout restart deployment httpbin fortio
```

### Issue: Circuit Breaker Not Triggering

**Symptoms:** No 503 errors during load test

**Solutions:**
```bash
# Verify destination rule is applied
kubectl get destinationrule httpbin-circuit-breaker -o yaml

# Check connection pool settings
kubectl describe destinationrule httpbin-circuit-breaker

# Increase concurrent connections in test
# Change -c value to exceed maxConnections
```

### Issue: Load Not Distributed Evenly

**Symptoms:** Some pods receive significantly more requests

**Solutions:**
```bash
# Verify all pods are ready
kubectl get pods -l app=httpbin

# Check service endpoints
kubectl get endpoints httpbin

# Verify destination rule
kubectl get destinationrule httpbin-lb-round-robin -o yaml

# Wait longer for distribution to stabilize (send 500+ requests)
```

---

## 📚 Additional Resources

- [Istio Documentation](https://istio.io/latest/docs/)
- [Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Circuit Breaking](https://istio.io/latest/docs/tasks/traffic-management/circuit-breaking/)
- [Load Balancing Options](https://istio.io/latest/docs/reference/config/networking/destination-rule/#LoadBalancerSettings)
- [Fortio Documentation](https://github.com/fortio/fortio)

---

## 📝 Configuration Reference

### Circuit Breaker Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `maxConnections` | 10 | Maximum number of HTTP1/TCP connections |
| `http1MaxPendingRequests` | 10 | Maximum pending HTTP requests |
| `maxRequestsPerConnection` | 2 | Maximum requests per connection |
| `maxRetries` | 3 | Maximum retry attempts |
| `consecutive5xxErrors` | 3 | Errors before ejection |
| `interval` | 30s | Analysis interval |
| `baseEjectionTime` | 30s | Minimum ejection duration |
| `maxEjectionPercent` | 100 | Maximum percentage of hosts that can be ejected |

### Load Balancer Algorithms

| Algorithm | Use Case |
|-----------|----------|
| `ROUND_ROBIN` | Equal distribution across all instances |
| `LEAST_REQUEST` | Send to instance with fewest active requests |
| `RANDOM` | Random selection |
| `PASSTHROUGH` | Forward to original destination |

---

## 🎓 Learning Outcomes

After completing this guide, you will understand:

✅ How to configure Istio DestinationRules  
✅ Load balancing strategies in service mesh  
✅ Circuit breaker patterns for resilience  
✅ Connection pool management  
✅ Outlier detection and pod ejection  
✅ Load testing with Fortio  
✅ Monitoring Istio traffic metrics  

---

## 📄 License

This project is provided as-is for educational purposes.

---

**Happy Service Meshing! 🚀**
