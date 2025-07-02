oc # Troubleshooting Guide: Spring Boot OpenShift Helm Chart

This document contains common issues encountered while deploying Spring Boot applications on OpenShift using this Helm chart and their solutions.

## Issue 1: DeploymentConfig Deprecation Warning

### Problem
```
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
Error from server (BadRequest): no deployment exists for deploymentConfig "app1-springboot-image-builder"
```

### Root Cause
- DeploymentConfig is deprecated in newer OpenShift versions (4.14+)
- Modern OpenShift prefers standard Kubernetes Deployment resources

### Solution
1. **Update API Version and Kind** in `templates/deploymentconfig.yaml`:
   ```yaml
   # Before
   apiVersion: apps.openshift.io/v1
   kind: DeploymentConfig
   
   # After
   apiVersion: apps/v1
   kind: Deployment
   ```

2. **Update Selector Format**:
   ```yaml
   # Before
   selector:
     app: "{{ include "springboot-ocdemo.name" . }}"
   
   # After
   selector:
     matchLabels:
       app: "{{ include "springboot-ocdemo.name" . }}"
   ```

3. **Remove OpenShift-specific Triggers**:
   ```yaml
   # Remove these sections completely
   triggers:
     - type: ConfigChange
     - type: ImageChange
       imageChangeParams:
         automatic: true
         containerNames:
           - "{{ include "springboot-ocdemo.name" . }}"
         from:
           kind: ImageStreamTag
           name: "{{ include "springboot-ocdemo.fullname" . }}:latest"
   ```

4. **Update HPA Reference** in `templates/hpa.yaml`:
   ```yaml
   # Before
   scaleTargetRef:
     apiVersion: apps.openshift.io/v1
     kind: DeploymentConfig
   
   # After
   scaleTargetRef:
     apiVersion: apps/v1
     kind: Deployment
   ```

5. **Rename File**: Rename `deploymentconfig.yaml` to `deployment.yaml` for clarity.

## Issue 2: Image Pull Errors

### Problem
```
Error: container "springboot-image-builder" in pod is waiting to start: trying and failing to pull image
ImagePullBackOff: Failed to pull image "app1-springboot-image-builder:latest"
```

### Root Cause
- Deployment was trying to pull from Docker Hub instead of OpenShift internal registry
- Missing full registry path in image reference

### Solution
Update the image reference in `templates/deployment.yaml`:
```yaml
# Before (incorrect)
image: "{{ include "springboot-ocdemo.fullname" . }}:latest"

# After (correct)
image: "image-registry.openshift-image-registry.svc:5000/{{ .Release.Namespace }}/{{ include "springboot-ocdemo.fullname" . }}:latest"
```

Also update the `imagePullPolicy`:
```yaml
# Change from IfNotPresent to Always for development
imagePullPolicy: "{{ .Values.image.pullPolicy | default "Always" }}"
```

## Issue 3: BuildConfig and ImageStream Naming Mismatch

### Problem
```
Error: bc/app1-springboot-image-builder is pushing to istag/springbootoc-springboot-image-builder:latest, but the image stream for that tag does not exist
```

### Root Cause
- BuildConfig output was hardcoded to a different ImageStream name
- Inconsistent naming between BuildConfig and ImageStream

### Solution
1. **Update BuildConfig** in `templates/buildconfig.yaml`:
   ```yaml
   # Before (hardcoded)
   output:
     to:
       kind: ImageStreamTag
       name: {{ .Values.build.outputImageStream | quote }}
   
   # After (dynamic)
   output:
     to:
       kind: ImageStreamTag
       name: "{{ include "springboot-ocdemo.fullname" . }}:latest"
   ```

2. **Update values.yaml** (optional, since we're now using dynamic naming):
   ```yaml
   build:
     outputImageStream: springboot-image-builder:latest  # Simplified
   ```

## Issue 4: Helm Release State Issues

### Problem
```
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
Error: INSTALLATION FAILED: deployments.apps "app1-springboot-image-builder" already exists
```

### Root Cause
- Failed Helm releases leave behind orphaned resources
- Helm state becomes inconsistent with actual cluster resources

### Solution
1. **Clean up failed releases**:
   ```bash
   helm uninstall <release-name>
   ```

2. **Remove orphaned resources**:
   ```bash
   oc delete all -l app.kubernetes.io/instance=<release-name>
   ```

3. **Check for all Helm releases (including failed ones)**:
   ```bash
   helm list --all
   ```

4. **For stubborn resources, manually delete**:
   ```bash
   oc delete deployment <deployment-name>
   oc delete service <service-name>
   oc delete route <route-name>
   oc delete buildconfig <buildconfig-name>
   oc delete imagestream <imagestream-name>
   ```

## Issue 5: File Path Issues During Installation

### Problem
```
Error: INSTALLATION FAILED: open values-app1.yaml: The system cannot find the file specified
```

### Root Cause
- Running Helm commands from incorrect directory
- Values files not in the expected location

### Solution
1. **Navigate to correct directory**:
   ```bash
   cd path/to/helm/chart/directory
   ```

2. **Verify file exists**:
   ```bash
   ls -la values*.yaml
   ```

3. **Use correct Helm command syntax**:
   ```bash
   # Install with custom values file
   helm install <release-name> . -f values-app1.yaml
   
   # Install with inline values
   helm install <release-name> . --set build.git.uri=https://github.com/your/repo.git
   ```

## Issue 6: TLS Route Configuration

### Problem
Understanding different TLS termination options for Routes.

### Solution
OpenShift Routes support three TLS termination types:

1. **Edge Termination** (default in our chart):
   ```yaml
   tls:
     termination: edge
   ```
   - TLS terminated at router
   - Backend communication is HTTP

2. **Passthrough Termination**:
   ```yaml
   tls:
     termination: passthrough
   ```
   - TLS passes through to backend
   - Backend must handle HTTPS

3. **Reencrypt Termination**:
   ```yaml
   tls:
     termination: reencrypt
     destinationCACertificate: |-
       -----BEGIN CERTIFICATE-----
       # Backend CA certificate
       -----END CERTIFICATE-----
   ```
   - TLS terminated at router and re-encrypted to backend

## Best Practices for Avoiding Issues

### 1. Use Modern Kubernetes Resources
- Prefer `Deployment` over `DeploymentConfig`
- Use standard Kubernetes APIs when possible
- Only use OpenShift-specific resources when necessary (Routes, BuildConfigs, ImageStreams)

### 2. Image Reference Management
- Always use full registry paths for OpenShift internal images
- Use `imagePullPolicy: Always` for development environments
- Use `imagePullPolicy: IfNotPresent` for production

### 3. Naming Consistency
- Use Helm templating for consistent naming: `{{ include "chart.fullname" . }}`
- Ensure BuildConfig output matches ImageStream names
- Use release names to avoid conflicts between deployments

### 4. Helm Management
- Always check `helm list` before installing
- Clean up failed releases completely
- Use different release names for different environments
- Test with `helm template` before installing

### 5. Debugging Commands
```bash
# Check pod status and events
oc get pods
oc describe pod <pod-name>

# Check build status
oc get builds
oc logs build/<build-name>

# Check image streams
oc get imagestreams
oc describe imagestream <imagestream-name>

# Check routes
oc get routes
curl -k https://<route-url>/actuator/health

# Check Helm releases
helm list --all
helm status <release-name>
```

## Multiple Application Deployment

### Method 1: Different Release Names
```bash
# First application
helm install app1 ./helm

# Second application with different Git repo
helm install app2 ./helm \
  --set build.git.uri=https://github.com/your/second-repo.git \
  --set route.host=app2.apps.your-openshift-domain.com
```

### Method 2: Using Values Files
```bash
# Create separate values files
helm install app1 ./helm -f values-app1.yaml
helm install app2 ./helm -f values-app2.yaml
```

### Method 3: Different Namespaces
```bash
helm install app1 ./helm --namespace app1-ns --create-namespace
helm install app2 ./helm --namespace app2-ns --create-namespace
```

## Internal Service Communication

To access your Spring Boot application from within the cluster:

```bash
# Using service name (same namespace)
curl http://<release-name>-springboot-image-builder:8080

# Using FQDN (cross-namespace)
curl http://<release-name>-springboot-image-builder.<namespace>.svc.cluster.local:8080

# Test health endpoint
curl http://<service-name>:8080/actuator/health

# From a temporary pod
oc run curl-test --image=curlimages/curl -i --tty --rm -- sh
```

---

**Note**: Keep this troubleshooting guide updated as you encounter new issues or find better solutions.

## Issue 7: App2 Deployment - Complete Troubleshooting Case Study

### Background
This section documents the complete troubleshooting process for deploying a second Spring Boot application (app2) using the same Helm chart, including all issues encountered and their resolutions.

### Initial Problem: Git Repository Access Issue

#### Problem
```
build.build.openshift.io/app2-springboot-image-builder-1   Source   Git@main   Failed (FetchSourceFailed)   About a minute ago   1s
```

#### Root Cause
- The Git repository `https://github.com/abhishekyavi/clinicalsapi.git` was private
- OpenShift BuildConfig couldn't access the repository

#### Solution
1. **Make Repository Public**: User made the repository public in GitHub settings
2. **Verify Repository Access**: Confirmed repository was accessible without authentication

### Resource Cleanup and Fresh Deployment

#### Problem
- Previous failed deployments left orphaned resources
- Helm releases were in failed state
- Multiple conflicting resources existed

#### Commands Executed for Cleanup
```bash
# Check all resources
oc get all

# Delete everything in the namespace
oc delete all --all

# Clean up Helm releases
helm list --all
helm uninstall app1
helm uninstall app2

# Verify cleanup
oc get all
```

### Image Pull Issues with Duplicate Templates

#### Problem
```
app2-springboot-image-builder-7fb44c54cd-nxtz7   0/1     ImagePullBackOff   0          3m27s

Error: Failed to pull image "app2-springboot-image-builder:latest": 
requested access to the resource is denied
```

#### Root Cause Analysis
1. **Checked Pod Details**:
   ```bash
   oc get pods -l app=springboot-image-builder
   oc describe pod app2-springboot-image-builder-7fb44c54cd-nxtz7
   ```

2. **Found Image Reference Issue**: Pod was trying to pull from Docker Hub instead of OpenShift registry
   - Expected: `image-registry.openshift-image-registry.svc:5000/abhishekyavi2015-dev/app2-springboot-image-builder:latest`
   - Actual: `app2-springboot-image-builder:latest`

3. **Discovered Duplicate Templates**:
   ```bash
   # Generated template analysis
   helm template app2 . -f values-app2.yaml
   ```
   
   Found two Deployment resources:
   - `templates/deployment.yaml` (incorrect - missing registry path)
   - `templates/deploymentconfig.yaml` (correct - full registry path)

#### Solution
1. **Identified Conflicting Templates**:
   ```bash
   ls templates/
   # Output showed both deployment.yaml and deploymentconfig.yaml
   ```

2. **Removed Incorrect Template**:
   ```bash
   rm templates/deployment.yaml
   ```

3. **Upgraded Deployment**:
   ```bash
   helm upgrade app2 . -f values-app2.yaml
   ```

### Verification Commands

#### Build Status Check
```bash
# Check build status
oc get builds
oc logs -f build/app2-springboot-image-builder-1

# Verify ImageStream creation
oc get imagestream
```

#### Deployment Status Check
```bash
# Check all app2 resources
oc get all -l app.kubernetes.io/instance=app2

# Check pod status
oc get pods -l app=springboot-image-builder

# Verify deployment details
oc describe deployment app2-springboot-image-builder
```

#### Route and Service Verification
```bash
# Check route
oc get route app2-springboot-image-builder

# Test application health (if accessible)
curl -k https://$(oc get route app2-springboot-image-builder -o jsonpath='{.spec.host}')/actuator/health
```

### Key Lessons Learned

#### 1. Repository Access
- **Always verify Git repository accessibility** before deploying
- Private repositories require authentication setup in OpenShift
- Making repositories public is the simplest solution for development

#### 2. Template Management
- **Avoid duplicate templates** with similar purposes
- Use consistent naming conventions
- `deployment.yaml` vs `deploymentconfig.yaml` can cause conflicts
- Always use `helm template` to verify generated manifests

#### 3. Image Reference Patterns
- **OpenShift internal registry path is crucial**: `image-registry.openshift-image-registry.svc:5000/namespace/imagename:tag`
- Missing registry path causes Docker Hub pull attempts
- Verify ImageStream creation before deployment

#### 4. Systematic Troubleshooting Process
1. **Check build logs first**: `oc logs build/<build-name>`
2. **Verify ImageStream creation**: `oc get imagestream`
3. **Check pod events**: `oc describe pod <pod-name>`
4. **Analyze generated templates**: `helm template <release> . -f <values-file>`
5. **Clean up completely** before retrying

### Commands for Multi-App Deployment

#### Complete Workflow for Deploying Both Apps
```bash
# Clean environment
oc delete all --all
helm uninstall app1 app2 (if they exist)

# Deploy app1
helm install app1 . -f values-app1.yaml

# Wait for app1 to be ready
oc get pods -w

# Deploy app2  
helm install app2 . -f values-app2.yaml

# Monitor app2 deployment
oc get pods -w
oc get builds -w

# Verify both applications
oc get all
helm list
```

## Issue 8: Readiness Probe Failures - Complete Troubleshooting Guide

### Problem
Pod shows as `0/1 Running` but never becomes Ready, with readiness probe failures and eventual CrashLoopBackOff.

```
aap2-springboot-image-builder-66bb5bc8d9-78cwq   0/1     CrashLoopBackOff   5 (41s ago)   7m21s
```

### Detailed Investigation Process

#### Step 1: Check Pod Status and Events
```bash
# Check pod status
oc get pods -l app=springboot-image-builder

# Get detailed pod information
oc describe pod <pod-name>
```

**Example Output Analysis:**
```
Events:
  Warning  Unhealthy  58s (x5 over 2m38s)  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 404
  Warning  Unhealthy  58s (x7 over 2m38s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 404
  Normal   Killing    58s (x2 over 2m18s)  kubelet  Container springboot-image-builder failed liveness probe, will be restarted
```

#### Step 2: Examine Application Logs
```bash
# Check current logs
oc logs <pod-name>

# Check logs from previous container instance
oc logs <pod-name> --previous

# Follow logs in real-time
oc logs -f <pod-name>
```

**Key Log Analysis Points:**
1. **Application Startup Success**: Look for `Started ClinicalsapiApplication in X seconds`
2. **Spring Boot Actuator**: Look for `Exposing 13 endpoints beneath base path '/actuator'`
3. **Tomcat Port**: Confirm `Tomcat started on port 8080`

#### Step 3: Test Endpoints Inside Container
```bash
# Test the health endpoint from inside the container
oc exec <pod-name> -- curl -s http://localhost:8080/actuator/health

# Test the root endpoint
oc exec <pod-name> -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/

# Test API endpoints
oc exec <pod-name> -- curl -s http://localhost:8080/api/patients
```

### Root Cause Analysis

#### Issue 1: Missing Spring Boot Actuator
**Problem**: Application doesn't have `/actuator/health` endpoint
```
{"timestamp":"2025-07-02T03:39:56.503+00:00","status":404,"error":"Not Found","path":"/actuator/health"}
```

**Solution**: Application needs Spring Boot Actuator dependency:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

#### Issue 2: Wrong Probe Endpoint
**Problem**: Using root path `/` which returns 404
```yaml
readinessProbe:
  httpGet:
    path: /  # This returns 404
    port: 8080
```

**Solution**: Use proper health endpoint once Actuator is available:
```yaml
readinessProbe:
  httpGet:
    path: /actuator/health  # Proper health endpoint
    port: 8080
```

### Complete Solution Workflow

#### Step 1: Update Probe Configuration
```yaml
# values-app2.yaml
livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 30

readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 30
```

#### Step 2: Apply Configuration Changes
```bash
# Upgrade Helm deployment with new configuration
helm upgrade app2 . -f values-app2.yaml

# Monitor the new pod creation
oc get pods -w

# Check the new pod logs
oc logs -f <new-pod-name>
```

#### Step 3: Verify Successful Deployment
```bash
# Check pod becomes ready
oc get pods -l app=springboot-image-builder

# Expected output:
# aap2-springboot-image-builder-5c9847f6df-jgcnp   1/1     Running   0   84s

# Test health endpoint
oc exec <pod-name> -- curl -s http://localhost:8080/actuator/health

# Expected output:
# {"status":"UP","groups":["liveness","readiness"]}
```

### External Access Verification

#### Step 1: Check Route Configuration
```bash
# Get external routes
oc get routes

# Test external health endpoint (Windows PowerShell)
Invoke-WebRequest -Uri "https://<route-host>/actuator/health"

# Test API endpoints externally
Invoke-WebRequest -Uri "https://<route-host>/api/patients"
```

#### Step 2: Browser and Postman URLs
**Base URL**: `https://aap2-springboot-image-builder-abhishekyavi2015-dev.apps.rm2.thpm.p1.openshiftapps.com`

**Available Endpoints**:
- Health Check: `GET /actuator/health`
- Patients API: `GET /api/patients`
- Clinical Data: `GET /api/clinicaldata`
- H2 Console: `GET /h2-console`

### Probe Configuration Best Practices

#### 1. Proper Timing Configuration
```yaml
livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 30    # Wait for app startup
  periodSeconds: 10          # Check every 10 seconds
  timeoutSeconds: 30         # Allow 30 seconds for response
  failureThreshold: 3        # Restart after 3 failures

readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 30    # Wait for app startup
  periodSeconds: 10          # Check every 10 seconds
  timeoutSeconds: 30         # Allow 30 seconds for response
  failureThreshold: 3        # Mark unready after 3 failures
```

#### 2. Spring Boot Application Requirements
**Required Dependencies**:
```xml
<!-- For health endpoints -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<!-- For web application -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
```

**Optional Configuration** (application.yml):
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always
```

### Troubleshooting Commands Cheat Sheet

```bash
# Pod Status and Events
oc get pods -l app=springboot-image-builder
oc describe pod <pod-name>

# Application Logs
oc logs <pod-name>
oc logs <pod-name> --previous
oc logs -f <pod-name>

# Test Endpoints Internally
oc exec <pod-name> -- curl -s http://localhost:8080/actuator/health
oc exec <pod-name> -- curl -s http://localhost:8080/api/patients

# Check External Access
oc get routes
Invoke-WebRequest -Uri "https://<route-host>/actuator/health"

# Helm Operations
helm upgrade <release-name> . -f <values-file>
helm status <release-name>
helm rollback <release-name> <revision>

# Build and ImageStream Status
oc get builds
oc get imagestreams
oc logs build/<build-name>

# Complete Cleanup (if needed)
helm uninstall <release-name>
oc delete all -l app.kubernetes.io/instance=<release-name>
```

### Error Patterns and Solutions

| Error Pattern | Root Cause | Solution |
|---------------|------------|----------|
| `HTTP probe failed with statuscode: 404` | Endpoint doesn't exist | Add Spring Boot Actuator or change endpoint |
| `context deadline exceeded` | Slow application startup | Increase `initialDelaySeconds` |
| `CrashLoopBackOff` | Repeated probe failures | Fix endpoint or probe configuration |
| `connection refused` | Application not listening | Check port configuration |
| `Application started in X seconds` but probe fails | Wrong endpoint path | Verify endpoint is actually available |

### Monitoring and Alerting

#### Health Check Monitoring
```bash
# Continuous monitoring script
while true; do
  echo "$(date): $(oc get pods -l app=springboot-image-builder --no-headers)"
  sleep 10
done

# External endpoint monitoring
while true; do
  status=$(curl -s -o /dev/null -w "%{http_code}" https://<route-host>/actuator/health)
  echo "$(date): Health endpoint returned $status"
  sleep 30
done
```

This comprehensive troubleshooting guide covers the complete investigation and resolution process for readiness probe failures in Spring Boot applications deployed on OpenShift.