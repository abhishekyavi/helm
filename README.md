# Spring Boot OpenShift Helm Chart

This Helm chart builds and deploys a Spring Boot application to OpenShift using Source-to-Image (S2I) and OpenShift resources.

## Features

- **BuildConfig**: Builds your app from a Git repository using S2I.
- **ImageStream**: Manages application images.
- **DeploymentConfig**: Deploys and manages your application pods.
- **Service**: Exposes your application internally.
- **Route**: Exposes your application externally.
- **Resource Requests/Limits**: Configurable CPU and memory.
- **Liveness/Readiness Probes**: Health checks for your application.

## Usage

### 1. Prerequisites

- OpenShift cluster
- Helm 3.x installed
- Access to a Git repository with a Spring Boot app

### 2. Configuration

Edit [`values.yaml`](helm/values.yaml) to set your Git repo, image, resources, probes, and route.

Example:
```yaml
build:
  enabled: true
  git:
    uri: https://github.com/your/repo.git
    ref: master
  strategy: Source
  outputImageStream: your-image:latest

service:
  name: your-app
  type: ClusterIP
  port: 8080

route:
  enabled: true
  host: your-app.apps.your-openshift-domain.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi

livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 30

readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

### 3. Install the Chart

```sh
helm install <release-name> ./helm
```

### 4. Upgrade the Chart

```sh
helm upgrade <release-name> ./helm
```

### 5. Uninstall

```sh
helm uninstall <release-name>
```

## Directory Structure

```
helm/
  Chart.yaml
  values.yaml
  templates/
    _helpers.tpl
    buildconfig.yaml
    deploymentconfig.yaml
    imagestream.yaml
    route.yaml
    service.yaml
```

## Notes

- Make sure your Spring Boot app exposes `/actuator/health` on port 8080.
- Adjust resource requests/limits and probe settings as needed for your workload.
- For HPA support, add an `hpa` section to `values.yaml` and create a `templates/hpa.yaml` file.

---

**For more details, see the comments in each file.**
- Made chnages in this branch as such any number spring applications can be deployed using the same templates and changeing only the values.yaml files.
- its working code
