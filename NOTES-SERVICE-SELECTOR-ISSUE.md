# Service Selector Issue - Quick Notes

## Issue Summary
**Problem**: Multiple Spring Boot apps (app1, app2) sharing same service endpoints causing 404 errors and inconsistent API responses.

**Root Cause**: Both apps used identical pod labels (`app=springboot-image-builder`) from shared Helm chart, causing services to load-balance between wrong pods.

## Key Discovery Commands
```bash
# Found multiple endpoints for single service
oc get endpoints app2-springboot-image-builder
# Output: 10.130.11.203:8080,10.130.11.238:8080 (2 IPs for 1 expected pod)

# Revealed identical labels on both apps
oc get pods -l app=springboot-image-builder --show-labels
# Both app1 and app2 pods had: app=springboot-image-builder
```

## Solution
**Changed from generic to specific labels:**

### Before (Problem):
```yaml
# Service selector - same for both apps
selector:
  app: "{{ include "springboot-ocdemo.name" . }}"  # = springboot-image-builder

# Pod labels - same for both apps  
labels:
  app: "{{ include "springboot-ocdemo.name" . }}"  # = springboot-image-builder
```

### After (Fixed):
```yaml
# Service selector - unique per release
selector:
  app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
  app.kubernetes.io/instance: "{{ .Release.Name }}"  # app1 or app2

# Pod labels - unique per release
labels:
  app.kubernetes.io/name: "{{ include "springboot-ocdemo.name" . }}"
  app.kubernetes.io/instance: "{{ .Release.Name }}"  # app1 or app2
```

## Implementation Steps
```bash
# 1. Update templates/service.yaml and templates/deploymentconfig.yaml
# 2. Handle immutable selector issue
helm uninstall app1
helm uninstall app2

# 3. Reinstall with new labels
helm install app1 . -f values-app1.yaml
helm install app2 . -f values-app2.yaml

# 4. Verify fix
oc get pods --show-labels
oc get endpoints
```

## Files Modified
- `templates/service.yaml` - Updated selector
- `templates/deploymentconfig.yaml` - Updated selector and pod labels

## Verification Results
```bash
# Before: Both services had multiple endpoints
app1-service: 10.130.11.203:8080,10.130.11.238:8080
app2-service: 10.130.11.203:8080,10.130.11.238:8080

# After: Each service has only its own pod
app1-service: 10.128.10.105:8080
app2-service: 10.130.11.203:8080
```

## Key Lesson
**Always use release-specific labels when deploying multiple instances of same Helm chart:**
- Include `app.kubernetes.io/instance: "{{ .Release.Name }}"` in selectors
- Prevents resource conflicts between releases
- Test with multiple releases before production

## Quick Reference Commands
```bash
# Investigation
oc get endpoints <service-name>
oc get pods --show-labels
oc get pods -o wide

# Testing
oc exec <pod> -- curl http://localhost:8080/api/patients
curl https://<external-url>/api/patients

# Deployment
helm uninstall <release>
helm install <release> . -f values-<app>.yaml
```

## Status: ✅ RESOLVED
- External APIs working consistently
- Services properly isolated per application
- Multi-application deployment functional
