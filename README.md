
## 1. Overview

This project demonstrates containerization and safe deployment of a simple Python HTTP service using Docker and Kubernetes.

The application provides three endpoints:

- `/health` - checks whether the application process is alive.
- `/ready` - returns 200 only when the application is ready to receive traffic; otherwise it returns 503.
- `/version` - returns the configured application version and instance/pod information when the release is ready.

The demo uses the same service code and the same version-tagged image (`yoyo-service:1.0`) for all releases. Environment variables are used to simulate three different release behaviors.

| Release | Behavior |
| --- | --- |
| v1 | Ready immediately |
| v2 | Healthy immediately but becomes ready only after 30 seconds |
| v3-broken | Process stays healthy but readiness fails indefinitely |

The assessment demonstrates Docker image execution, direct endpoint behavior, Kubernetes Deployment and Service, multiple replicas, liveness and readiness probes, rolling updates, continuous traffic, failed rollout detection, and rollback/recovery.

A key part of the demonstration is the difference between **direct release testing** and **Kubernetes Service traffic**. Direct Docker checks show the actual 503 response of an unready release. Kubernetes Service traffic, however, is routed to ready pods, which protects users from an unready or broken new release.

---

## 2. Project Structure

```text
devops-assessment/
├── app/
│   ├── app.py
│   └── Dockerfile
├── k8s/
│   ├── deployment.yaml
│   └── rollout-check.ps1
├── traffic-check.ps1
└── README.md
```

---

## 3. Release Configuration

The release behavior is controlled using these environment variables:

- `APP_VERSION` - identifies the release.
- `READY_DELAY_SECONDS` - controls how long the application waits before becoming ready.
- `NEVER_READY` - when set to `true`, the application remains unready indefinitely.

No separate image build is required for v1, v2, and v3-broken.

---

# 4. Docker Demonstration

The Docker demonstration tests the release container directly. This makes the application's actual health and readiness behavior clearly visible.

## 4.1 v1 - Ready Immediately

Start v1:

```powershell
docker run --rm -d --name yoyo-cont -p 8080:8080 -e APP_VERSION=v1 -e READY_DELAY_SECONDS=0 -e NEVER_READY=false yoyo-service:1.0
```

Check the endpoints:

```powershell
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/health
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/ready
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/version
```

Expected result:

```text
healthy HTTP:200
ready HTTP:200
version=v1 instance=<container-id> HTTP:200
```

v1 is alive and ready immediately.

Stop v1:

```powershell
docker stop yoyo-cont
```

---

## 4.2 v2 - Ready After 30 Seconds

Start v2:

```powershell
docker run --rm -d --name yoyo-cont -p 8080:8080 -e APP_VERSION=v2 -e READY_DELAY_SECONDS=30 -e NEVER_READY=false yoyo-service:1.0
```

Immediately check the same endpoints:

```powershell
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/health
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/ready
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/version
```

During the first 30 seconds, the expected result is:

```text
healthy HTTP:200
not ready HTTP:503
not ready HTTP:503
```

This proves that the v2 process is alive, but it is not yet ready to receive traffic.

After 30 seconds, run the same commands again:

```powershell
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/health
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/ready
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/version
```

Expected result:

```text
healthy HTTP:200
ready HTTP:200
version=v2 instance=<container-id> HTTP:200
```

This demonstrates the required v2 transition from **503 not ready** to **200 ready**.

Stop v2:

```powershell
docker stop yoyo-cont
```

---

## 4.3 v3-broken - Healthy but Never Ready

Start v3-broken:

```powershell
docker run --rm -d --name yoyo-cont -p 8080:8080 -e APP_VERSION=v3-broken -e READY_DELAY_SECONDS=0 -e NEVER_READY=true yoyo-service:1.0
```

Check the same endpoints:

```powershell
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/health
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/ready
curl.exe -s -w " HTTP:%{http_code}" http://localhost:8080/version
```

Expected result:

```text
healthy HTTP:200
not ready HTTP:503
not ready HTTP:503
```

This is the intentionally broken release. The process is still alive, so `/health` returns 200, but `/ready` continues returning 503. This means the release must not receive normal production traffic.

Stop v3-broken:

```powershell
docker stop yoyo-cont
```

---

# 5. Kubernetes Design

The Kubernetes deployment runs two application replicas and uses a rolling update strategy.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

The readiness probe calls `/ready`, while the liveness probe calls `/health`.

### Why readiness and liveness are separate

`/health` answers: **Is the application process alive?**

`/ready` answers: **Is this application instance safe to receive traffic?**

This separation is important for v3-broken. Its process is alive, but it must not receive traffic.

### Why `maxUnavailable: 0`

The rollout is configured not to intentionally reduce the number of available replicas while replacing the old release.

### Why `maxSurge: 1`

Kubernetes can temporarily create one additional pod during the rollout. The new pod can start and pass readiness before the healthy old pod is removed.

---

# 6. Continuous Kubernetes Traffic Test

`traffic-check.ps1` is intentionally a **Service-level traffic test**.

It sends requests to:

```text
http://yoyo-service/version
```

This script should remain unchanged because its purpose is to demonstrate availability from the Kubernetes Service perspective.

Start it in a separate PowerShell window:

```powershell
cd C:\Users\SURAJ\devops-assessment
powershell -ExecutionPolicy Bypass -File .\traffic-check.ps1 -DurationSeconds 3600
```

For a shorter recording, for example:

```powershell
powershell -ExecutionPolicy Bypass -File .\traffic-check.ps1 -DurationSeconds 90
```

The script reports total requests, successes, failures, and versions observed.

**Important:** This Service-level traffic test is not expected to show v2's direct 503 response. Kubernetes removes unready pods from normal Service traffic. The Docker demonstration proves the direct 503 behavior, while this traffic test proves Kubernetes protects availability.

---

# 7. Kubernetes v1 - Healthy Baseline

Deploy v1:

```powershell
kubectl set env deployment/yoyo-service APP_VERSION=v1 READY_DELAY_SECONDS=0 NEVER_READY=false
```

Check rollout status:

```powershell
kubectl rollout status deployment/yoyo-service --timeout=10s
```

Run the rollout checker:

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 10
```

Inspect pods:

```powershell
kubectl get pods
```

Check the Service:

```powershell
kubectl exec traffic-client -- curl -s http://yoyo-service/health
kubectl exec traffic-client -- curl -s http://yoyo-service/ready
kubectl exec traffic-client -- curl -s http://yoyo-service/version
```

Expected result: v1 becomes ready immediately and the rollout succeeds.

---

# 8. Kubernetes v1 to v2 Rolling Update

Deploy v2:

```powershell
kubectl set env deployment/yoyo-service APP_VERSION=v2 READY_DELAY_SECONDS=30 NEVER_READY=false
```

Immediately inspect the pods:

```powershell
kubectl get pods
```

The new v2 pod should initially be running but unready:

```text
0/1 Running
```

A short status check can intentionally demonstrate that v2 has not completed yet:

```powershell
kubectl rollout status deployment/yoyo-service --timeout=10s
```

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 10
```

Because v2 intentionally requires 30 seconds before becoming ready, a 10-second check may time out at this stage. That is expected.

After sufficient time, verify successful completion using a longer timeout:

```powershell
kubectl rollout status deployment/yoyo-service --timeout=60s
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 60
kubectl get pods
```

Check the Service:

```powershell
kubectl exec traffic-client -- curl -s http://yoyo-service/health
kubectl exec traffic-client -- curl -s http://yoyo-service/ready
kubectl exec traffic-client -- curl -s http://yoyo-service/version
```

### Why Kubernetes may show 200 while the new v2 pod is unready

The Docker test directly proved that v2 returns `/ready -> 503` during its first 30 seconds.

In Kubernetes, however, `yoyo-service` routes normal traffic to ready pods. While the new v2 pod is unready, existing healthy pods continue handling requests. Once v2 passes readiness, Kubernetes can include it in Service traffic and continue the rollout.

This is the safe rollout behavior the assessment is designed to demonstrate.

---

# 9. Kubernetes v3-broken - Failed Release

Deploy v3-broken:

```powershell
kubectl set env deployment/yoyo-service APP_VERSION=v3-broken READY_DELAY_SECONDS=0 NEVER_READY=true
```

Inspect pods:

```powershell
kubectl get pods
```

The new v3-broken pod should remain unready:

```text
0/1 Running
```

Check rollout status:

```powershell
kubectl rollout status deployment/yoyo-service --timeout=10s
```

Run the rollout checker:

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 10
```

The rollout should fail or time out because v3-broken never passes readiness.

Check the Service:

```powershell
kubectl exec traffic-client -- curl -s http://yoyo-service/health
kubectl exec traffic-client -- curl -s http://yoyo-service/ready
kubectl exec traffic-client -- curl -s http://yoyo-service/version
```

These Service requests can still return successful responses because Kubernetes continues routing requests to ready healthy pods rather than the new broken pod.

The Docker test proved the release itself behaves as:

```text
/health -> 200 healthy
/ready  -> 503 not ready
```

The Kubernetes test proves that this broken release does not have to take down the healthy Service.

---

# 10. Rollout Checker

The custom `rollout-check.ps1` script gives a clear success/failure result for the deployment.

For a completed healthy rollout:

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 60
```

Expected result: successful rollout with exit code 0.

For v3-broken:

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 10
```

Expected result: failure/timeout with a non-zero exit code.

This type of result can be used by a CI/CD pipeline to decide whether a deployment succeeded or requires recovery.

---

# 11. Rollback and Recovery

Recover from v3-broken:

```powershell
kubectl rollout undo deployment/yoyo-service
```

Wait for the rollback:

```powershell
kubectl rollout status deployment/yoyo-service --timeout=60s
```

Verify pods:

```powershell
kubectl get pods
```

Verify the Service:

```powershell
kubectl exec traffic-client -- curl -s http://yoyo-service/health
kubectl exec traffic-client -- curl -s http://yoyo-service/ready
kubectl exec traffic-client -- curl -s http://yoyo-service/version
```

Run the rollout checker again:

```powershell
powershell -ExecutionPolicy Bypass -File .\rollout-check.ps1 -TimeoutSeconds 60
```

If v3-broken was deployed immediately after v2, the rollback restores the previous healthy v2 revision.

---

# 12. What the Traffic Test Demonstrates

During the v1 to v2 rollout:

1. Healthy v1 pods initially serve traffic.
2. Kubernetes creates the new v2 pod.
3. v2 remains unready during its 30-second startup delay.
4. Kubernetes keeps Service traffic on ready pods.
5. v2 eventually passes readiness.
6. Kubernetes completes the rolling update.
7. Traffic moves to v2 without intentionally routing requests to an unready pod.

During the v3-broken rollout:

1. Kubernetes creates a v3-broken pod.
2. The application remains alive.
3. Readiness never succeeds.
4. Kubernetes does not consider that pod ready for normal Service traffic.
5. The rollout cannot successfully complete.
6. The rollout checker detects the problem.
7. The deployment is rolled back to the previous healthy release.

---

# 13. Recording / Demonstration Sequence

A clear 5-10 minute demonstration can follow this order:

1. Show Docker v1 and its three successful endpoint checks.
2. Show Docker v2 immediately: health 200, readiness 503.
3. After 30 seconds, show v2 readiness changing to 200.
4. Show Docker v3-broken: health 200, readiness 503.
5. Show the Kubernetes Deployment strategy and probes.
6. Deploy Kubernetes v1 as the healthy baseline.
7. Start `traffic-check.ps1` in a separate PowerShell window.
8. Deploy v2 and show the new pod initially `0/1`.
9. Show v2 eventually becoming ready and the rollout checker succeeding.
10. Show the traffic summary and that Service traffic remained available.
11. Deploy v3-broken and show its pod remaining `0/1`.
12. Show rollout status/checker failure for v3-broken.
13. Show healthy Service traffic remains protected.
14. Roll back to the previous healthy release.
15. Verify readiness, rollout completion, version, and traffic after recovery.

---

# 14. Key Design Decisions

### Same image for all releases

All three scenarios use `yoyo-service:1.0`. Environment variables simulate the release behavior, so separate image builds are unnecessary.

### Readiness controls traffic eligibility

A running process is not automatically considered ready. This prevents slow-starting or broken releases from receiving normal traffic.

### Rolling update protects availability

`maxUnavailable: 0` and `maxSurge: 1` allow the new release to be evaluated before healthy capacity is intentionally removed.

### Explicit rollback provides recovery

When v3-broken never becomes ready, the rollout is detected as failed and the deployment can be returned to the previous healthy revision.

---

# 15. Difficulty Encountered

One implementation difficulty was running and automating the assessment from Windows PowerShell while many Docker and Kubernetes examples are commonly written for Linux shells.

The solution was to use PowerShell scripts for continuous traffic and rollout validation while keeping the service behavior controlled through simple environment variables. This made the demonstration reproducible without changing the application design.

---

# 16. Production Improvements

For a production environment, useful improvements would include:

- Prometheus metrics and Grafana dashboards.
- Centralized application and Kubernetes logging.
- Alerts for readiness failures and rollout timeouts.
- CI/CD integration for automatic rollout validation.
- Deployment notifications.
- Automatic rollback or promotion rules based on health metrics.
- PodDisruptionBudget where appropriate.
- Ingress/load-balancer monitoring.
- A proper container registry with immutable image references.
- Image security scanning and policy enforcement.

The first production improvement I would prioritize is **monitoring and alerting for readiness and rollout failures**, so the team is notified immediately when a new release cannot safely receive traffic.

---

# 17. Final Result

This project demonstrates both sides of safe release handling:

**Direct application behavior:** v1 is ready immediately, v2 is healthy but unready for 30 seconds before becoming ready, and v3-broken remains healthy but never becomes ready.

**Kubernetes availability behavior:** readiness probes prevent unready releases from receiving normal Service traffic. A delayed release can become ready safely, while a permanently broken release is detected and can be rolled back without intentionally routing normal Service traffic to that broken pod.

Together, the Docker checks, Kubernetes rolling deployment, continuous traffic test, rollout checker, and rollback procedure demonstrate how to keep a service available during both a slow release and a broken release.
