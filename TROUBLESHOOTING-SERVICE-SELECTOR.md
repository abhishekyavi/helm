# Service Selector Issue Troubleshooting Guide

## Issue: Multiple Applications Sharing Service Endpoints

### Date: July 2, 2025

This document details the complete troubleshooting process for resolving service selector conflicts when deploying multiple applications using the same Helm chart.

---

## **Problem Description**

### Initial Symptoms:
1. **External URL returns 404**: Browser shows Spring Boot error page with 404 for `/api/patients`
2. **Inconsistent API responses**: Sometimes works, sometimes doesn't
3. **Internal container APIs work**: `curl` inside container returns valid JSON
4. **Multiple endpoints in service**: Service shows more endpoints than expected pods

### Error Messages:
```
Whitelabel Error Page
This application has no explicit mapping for /error, so you are seeing this as a fallback.

Wed Jul 02 10:21:53 UTC 2025
There was an unexpected error (type=Not Found, status=404).
```

---

## **Investigation Process**

### Step 1: Verify Internal API Functionality
```bash
# Get current pods
oc get pods -l app=springboot-image-builder

# Test API endpoint inside container
oc exec app2-springboot-image-builder-569f5f9d68-v2lk5 -- curl -s http://localhost:8080/api/patients
```

**Result**: API works perfectly inside container, returns full JSON response.

### Step 2: Check External Route Configuration
```bash
# Check route configuration
oc get route app2-springboot-image-builder -o yaml

# Check service configuration  
oc get service app2-springboot-image-builder -o yaml
```

**Findings**: Route and service configurations appeared correct.

### Step 3: Investigate Service Endpoints
```bash
# Check service endpoints
oc get endpoints app2-springboot-image-builder

# Output showed unexpected result:
# NAME                            ENDPOINTS                                AGE
# app2-springboot-image-builder   10.130.11.203:8080,10.130.11.238:8080   33m
```

**🚨 CRITICAL DISCOVERY**: Service had **two endpoints** but only one app2 pod expected.

### Step 4: Analyze Pod Labels
```bash
# Check all pods with labels
oc get pods -l app=springboot-image-builder --show-labels

# Output revealed the issue:
# NAME                                             LABELS
# app1-springboot-image-builder-58656b794d-52nh7   app=springboot-image-builder,pod-template-hash=58656b794d
# app2-springboot-image-builder-569f5f9d68-v2lk5   app=springboot-image-builder,pod-template-hash=569f5f9d68
```

**🎯 ROOT CAUSE IDENTIFIED**: Both app1 and app2 pods have identical `app=springboot-image-builder` label!

### Step 5: Check Pod IP Addresses
```bash
# Get pods with IP addresses
oc get pods -l app=springboot-image-builder -o wide

# Confirm IPs match service endpoints:
# app1-springboot-image-builder: 10.130.11.203
# app2-springboot-image-builder: 10.130.11.238
```

**Confirmed**: Service was load-balancing between both applications!

---

## **Root Cause Analysis**

### The Problem:
1. **Shared Chart Template**: Both applications use the same Helm chart
2. **Identical Labels**: Chart generates same pod labels for both releases
3. **Service Selector Conflict**: Service selectors match pods from both applications
4. **Load Balancing Issue**: External requests randomly route to app1 or app2

### Technical Details:

#### Original Service Template (`templates/service.yaml`):
```yaml
spec:
  selector:
    app: "{{ include "springboot-ocdemo.name" . }}"
```

#### Original Deployment Template (`templates/deploymentconfig.yaml`):
```yaml
template:
  metadata:
    labels:
      app: "{{ include "springboot-ocdemo.name" . }}"
```

#### Helper Template Resolution:
```yaml
{{- define "springboot-ocdemo.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}
```

**Result**: Both `app1` and `app2` releases generated `app: springboot-image-builder` labels.

---

## **Solution Implementation**

### Step 1: Update Service Selector
**File**: `templates/service.yaml`

**Before**:
```yaml
spec:
  selector:
    app: "{{ include "springboot-ocdemo.name" . }}"
```

**After**:
```yaml
spec:
  selector:
    app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
    app.kubernetes.io/instance: "{{ .Release.Name }}"
```

### Step 2: Update Deployment Labels
**File**: `templates/deploymentconfig.yaml`

**Before**:
```yaml
spec:
  selector:
    matchLabels:
      app: "{{ include "springboot-ocdemo.name" . }}"
  template:
    metadata:
      labels:
        app: "{{ include "springboot-ocdemo.name" . }}"
```

**After**:
```yaml
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
      app.kubernetes.io/instance: "{{ .Release.Name }}"
  template:
    metadata:
      labels:
        app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
        app.kubernetes.io/instance: "{{ .Release.Name }}"
```

### Step 3: Handle Deployment Selector Immutability
```bash
# Kubernetes error when trying to update existing deployment:
# Error: UPGRADE FAILED: cannot patch "app2-springboot-image-builder" with kind Deployment: 
# Deployment.apps "app2-springboot-image-builder" is invalid: spec.selector: Invalid value: 
# field is immutable

# Solution: Uninstall and reinstall
helm uninstall app2
helm uninstall app1
```

### Step 4: Reinstall Applications
```bash
# Reinstall both applications with new label structure
helm install app1 . -f values-app1.yaml
helm install app2 . -f values-app2.yaml
```

---

## **Verification Process**

### Step 1: Check Pod Separation
```bash
# Verify pods have unique labels
oc get pods --show-labels

# Expected output:
# app1-springboot-image-builder-xxx   app.kubernetes.io/instance=app1,app.kubernetes.io/name=springboot-image-builder
# app2-springboot-image-builder-xxx   app.kubernetes.io/instance=app2,app.kubernetes.io/name=springboot-image-builder
```

### Step 2: Verify Service Endpoints
```bash
# Check that each service has only its own pods
oc get endpoints

# Expected output:
# app1-springboot-image-builder   10.128.10.105:8080           56m
# app2-springboot-image-builder   10.130.11.203:8080           50m
```

### Step 3: Test External API Access
```bash
# Test app2 external URL
curl -s https://app2-springboot-image-builder-abhishekyavi2015-dev.apps.rm2.thpm.p1.openshiftapps.com/api/patients

# Expected: Valid JSON response with patient data
```

### Step 4: Verify API Endpoints Work
```bash
# Test various endpoints
curl -s https://app2-springboot-image-builder-abhishekyavi2015-dev.apps.rm2.thpm.p1.openshiftapps.com/api/clinicaldata
```

---

## **Complete Command Reference**

### Investigation Commands:
```bash
# Pod and service investigation
oc get pods -l app=springboot-image-builder
oc get pods -l app=springboot-image-builder --show-labels
oc get pods -l app=springboot-image-builder -o wide
oc get endpoints
oc get service app2-springboot-image-builder -o yaml
oc get route app2-springboot-image-builder -o yaml

# Internal API testing
oc exec <pod-name> -- curl -s http://localhost:8080/api/patients
oc exec <pod-name> -- curl -s http://localhost:8080/api/clinicaldata
oc exec <pod-name> -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/

# External API testing
curl -s https://<external-url>/api/patients
Invoke-WebRequest -Uri "https://<external-url>/api/patients"
```

### Solution Implementation Commands:
```bash
# Template updates (manual file editing required)
# Edit templates/service.yaml
# Edit templates/deploymentconfig.yaml

# Deployment updates
helm upgrade app2 . -f values-app2.yaml  # This will fail due to immutable selector
helm uninstall app2
helm uninstall app1

# Reinstallation
helm install app1 . -f values-app1.yaml
helm install app2 . -f values-app2.yaml

# Verification
oc get pods --show-labels
oc get endpoints
```

### Monitoring Commands:
```bash
# Watch deployments
oc get pods -w
oc get builds -w

# Check build status
oc get builds
oc logs -f build/<build-name>

# Test endpoints continuously
while true; do
  echo "$(date): Testing external API..."
  curl -s -o /dev/null -w "%{http_code}" https://<external-url>/api/patients
  sleep 5
done
```

---

## **Key Lessons Learned**

### 1. **Helm Chart Label Strategy**
- **Problem**: Using only chart-based labels leads to conflicts
- **Solution**: Always include release-specific labels
- **Best Practice**: Use `app.kubernetes.io/instance: {{ .Release.Name }}`

### 2. **Service Selector Specificity**
- **Problem**: Generic selectors match unintended pods
- **Solution**: Use multiple labels for precise targeting
- **Best Practice**: Combine `name` + `instance` labels

### 3. **Kubernetes Immutable Fields**
- **Problem**: Deployment selectors cannot be changed after creation
- **Solution**: Delete and recreate deployments
- **Best Practice**: Plan label strategy before initial deployment

### 4. **Multi-Application Deployments**
- **Problem**: Shared chart templates can cause resource conflicts
- **Solution**: Use release names in resource identification
- **Best Practice**: Test label selectors with multiple releases

### 5. **Troubleshooting Methodology**
1. **Verify internal functionality first** (container-level testing)
2. **Check resource configurations** (services, routes)
3. **Investigate resource relationships** (endpoints, selectors)
4. **Analyze labels and selectors** (root cause identification)
5. **Implement targeted fixes** (specific to root cause)

---

## **Prevention Strategies**

### 1. **Template Design**
```yaml
# Always use both name and instance in selectors
selector:
  app.kubernetes.io/name: "{{ include "chart.name" . }}"
  app.kubernetes.io/instance: "{{ .Release.Name }}"
```

### 2. **Testing Multiple Releases**
```bash
# Test chart with multiple releases before production
helm install test1 ./chart -f values-test1.yaml
helm install test2 ./chart -f values-test2.yaml

# Verify no resource conflicts
oc get endpoints
oc get pods --show-labels
```

### 3. **Label Validation**
```bash
# Verify unique labels per release
helm template app1 ./chart -f values-app1.yaml | grep -A 5 -B 5 "selector"
helm template app2 ./chart -f values-app2.yaml | grep -A 5 -B 5 "selector"
```

### 4. **Documentation**
- Document label strategies in chart README
- Include multi-release testing procedures
- Provide troubleshooting steps for common conflicts

---

## **Related Issues and References**

### Kubernetes Documentation:
- [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

### Helm Documentation:
- [Chart Template Guide](https://helm.sh/docs/chart_template_guide/)
- [Best Practices](https://helm.sh/docs/chart_best_practices/)

### OpenShift Documentation:
- [Routes](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
- [Services](https://docs.openshift.com/container-platform/latest/networking/understanding-networking.html)

---

## **Appendix: Complete File Changes**

### A. Modified `templates/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: "{{ include "springboot-ocdemo.fullname" . }}"
  labels:
    {{- include "springboot-ocdemo.labels" . | nindent 4 }}
spec:
  selector:
    app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
    app.kubernetes.io/instance: "{{ .Release.Name }}"
  ports:
    - protocol: TCP
      port: {{ .Values.service.port | default 8080 }}
      targetPort: {{ .Values.service.port | default 8080 }}
```

### B. Modified `templates/deploymentconfig.yaml`:
```yaml
# Deployment selector and pod labels sections updated
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
      app.kubernetes.io/instance: "{{ .Release.Name }}"
  template:
    metadata:
      labels:
        app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
        app.kubernetes.io/instance: "{{ .Release.Name }}"
    # ... rest of template unchanged
```

---

**Resolution Status**: ✅ **RESOLVED**
**External APIs**: ✅ **WORKING**
**Service Separation**: ✅ **CONFIRMED**
**Multi-Application Support**: ✅ **FUNCTIONAL**
