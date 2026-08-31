{{/* TTY bridge resource names and public URL helpers. */}}
{{- define "terminal-tty-bridge.name" -}}
{{- default "terminal-tty-bridge" .Values.ttyBridge.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "terminal-tty-bridge.fullname" -}}
{{- if .Values.ttyBridge.fullnameOverride -}}
{{- .Values.ttyBridge.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "terminal-tty-bridge.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "terminal-tty-bridge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "terminal-tty-bridge.selectorLabels" -}}
app: {{ include "terminal-tty-bridge.fullname" . }}
{{- end }}

{{- define "terminal-tty-bridge.labels" -}}
helm.sh/chart: {{ include "terminal-tty-bridge.chart" . }}
{{ include "terminal-tty-bridge.selectorLabels" . }}
app.kubernetes.io/name: {{ include "terminal-tty-bridge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{- define "terminal-tty-bridge.host" -}}
{{- default (printf "%s.%s" .Values.ttyBridge.ingress.hostPrefix (include "terminal-frontend.cloudDomain" .)) .Values.ttyBridge.ingress.host -}}
{{- end }}

{{- define "terminal-tty-bridge.origin" -}}
{{- include "terminal-frontend.scheme" . }}://{{ include "terminal-tty-bridge.host" . }}{{ include "terminal-frontend.portSuffix" . }}
{{- end }}

{{- define "terminal-tty-bridge.configMapName" -}}
{{- printf "%s-config" (include "terminal-tty-bridge.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "terminal-tty-bridge.ingressName" -}}
{{- default (include "terminal-tty-bridge.fullname" .) .Values.ttyBridge.ingress.name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "terminal-tty-bridge.agentBaseUrl" -}}
{{- $override := .Values.frontend.terminalConfig.ttyAgentBaseUrl | trim -}}
{{- if $override -}}
{{- $override -}}
{{- else if and .Values.ttyBridge.enabled .Values.ttyBridge.ingress.enabled -}}
{{- include "terminal-tty-bridge.origin" . -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end }}
