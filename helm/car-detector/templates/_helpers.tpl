{{- define "car-detector.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "car-detector.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "car-detector.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "car-detector.labels" -}}
app.kubernetes.io/name: {{ include "car-detector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "car-detector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- .Values.serviceAccount.name | default (include "car-detector.fullname" .) -}}
{{- else -}}
{{- .Values.serviceAccount.name | default "default" -}}
{{- end -}}
{{- end -}}