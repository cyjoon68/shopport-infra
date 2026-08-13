{{- define "shopport.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "shopport.fullname" -}}
{{- default (printf "%s-%s" .Release.Name (include "shopport.name" .)) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "shopport.labels" -}}
app.kubernetes.io/name: {{ include "shopport.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
shopport.io/environment: {{ .Values.environment | quote }}
{{- end }}

{{- define "shopport.image" -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .digest) -}}
{{- fail "image digest must be an immutable sha256 digest" -}}
{{- end -}}
{{- printf "%s@%s" .repository .digest -}}
{{- end }}

{{- define "shopport.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
fsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "shopport.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}

{{- define "shopport.topologySpread" -}}
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app.kubernetes.io/instance: {{ .Release.Name }}
      app.kubernetes.io/component: {{ .component }}
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      app.kubernetes.io/instance: {{ .Release.Name }}
      app.kubernetes.io/component: {{ .component }}
{{- end }}
