{{- define "springboot-ocdemo.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "springboot-ocdemo.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "springboot-ocdemo.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "springboot-ocdemo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end }}

{{- define "springboot-ocdemo.labels" -}}
app.kubernetes.io/name: {{ include "springboot-ocdemo.name" . }}
helm.sh/chart: {{ include "springboot-ocdemo.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}