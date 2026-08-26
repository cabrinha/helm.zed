{{- define "example.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "example.labels" -}}
app.kubernetes.io/name: {{ include "example.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
