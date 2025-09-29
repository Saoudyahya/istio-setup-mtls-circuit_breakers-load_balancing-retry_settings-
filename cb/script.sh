# Get fortio pod name
export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}')

# Test normal behavior first
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio curl -quiet http://httpbin:8000/get

# Trigger circuit breaker with concurrent requests
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 20 -qps 0 -n 200 -loglevel Warning http://httpbin:8000/get

# Test with delayed responses to trigger timeout-based circuit breaking
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 10 -qps 0 -n 100 -loglevel Warning http://httpbin:8000/delay/5