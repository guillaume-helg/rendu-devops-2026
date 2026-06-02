{{/*
Expand the name of the chart.
*/}}
{{- define "database.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We force it to release-name + "-mysql" so it matches the expected service name "miage-bank-mysql".
*/}}
{{- define "database.fullname" -}}
{{- printf "%s-mysql" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "database.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "database.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "database.selectorLabels" -}}
app.kubernetes.io/name: miage-bank
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
