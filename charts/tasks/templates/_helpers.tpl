{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "tasks.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tasks.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tasks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "tasks.labels" -}}
helm.sh/chart: {{ include "tasks.chart" . }}
{{ include "tasks.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "tasks.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tasks.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "tasks.serviceAccountName" -}}
{{ include (print .Chart.Name ".fullname") . }}
{{- end -}}

{{- define "tasks.globalHub" -}}
    {{- if not .Values.disableGlobalHub -}}
        {{- .Values.global.hub -}}
    {{- end -}}
{{- end -}}

{{- define "tasks.imageUrl" -}}
{{- include "tasks.globalHub" . }}{{ .Values.image.repository }}:{{ default .Values.image.tag .Chart.AppVersion -}}
{{- end -}}

{{- define "tasks.envParameters" -}}
{{- if not .Values.noGlobalConfigMapAndSecret }}
- name: "cm-config"
  default: ""
- name: "secret-config"
  default: ""
- name: "global-cm-config"
  default: ""
- name: "global-secret-config"
  default: ""
{{- end }}
{{- end -}}

{{- define "tasks.loadEnvParameters" -}}
{{- if .Values.global.proxy.enabled -}}
- configMapRef:
    name: tasks-proxy
{{- end }}
{{- if not .Values.noGlobalConfigMapAndSecret }}
- configMapRef:
    name: "$(params.global-cm-config)"
    optional: true
- secretRef:
    name: "$(params.global-secret-config)"
    optional: true
- configMapRef:
    name: "$(params.cm-config)"
    optional: true
- secretRef:
    name: "$(params.secret-config)"
    optional: true
{{- end }}
{{- if .Values.envFrom }}
{{ toYaml .Values.envFrom }}
{{- end -}}
{{- end -}}

{{- define "tasks.gitRepos" -}}
- name: git-url
- name: git-revision
  default: "develop"
- name: git-ssl-check
  default: "false"
{{- end }}

{{ define "task.gitCheckout" }}
- name: "git-checkout"
  image:  "{{ .Values.global.hub }}{{ .Values.global.image.git.repository }}:{{ .Values.global.image.git.tag }}"
  workingDir: "/git"
  command: ["sh", "-c"]
  args:
    - |-
        set -e
        # TODO: for the moment, the back is sending a git:// url.
        # Changing it here for the moment
        GIT_URL=`echo $(params.git-url) | sed 's/^git:/https:/'`
        /ko-app/git-init -url ${GIT_URL} \
                -revision $(params.git-revision) \
                -sslVerify=$(params.git-ssl-check) \
                -path /git
        git log -n 1 '--pretty=format:git_short_hash=%h git_hash=%H ' > /git/qgc-git-info
{{ end }}

{{ define "task.uploadEvidences" }}
{{- if not .Values.noEvidence }}
- name: upload-evidences
  envFrom:
    - secretRef:
        name: azure-secret
  image: {{ .Values.global.image.azure.repository }}:{{ .Values.global.image.azure.tag }}
  volumeMounts:
    - mountPath: /etc/podinfo
      name: podinfo
    {{ if not .Values.noGit }}
    - name: git
      mountPath: /git
    {{ end }}
  command: ["bash", "-c"]
  args:
    - |-
        # Any subsequent(*) commands which fail will cause the shell script to exit immediately
        set -e
        set -x
        AZ_OPTS=""
        if [ -z "$RELEASE_UID" ]; then
          CONTAINER_NAME="test-${NAMESPACE}-${UID}"
        else
          CONTAINER_NAME="release-${NAMESPACE}-${RELEASE_UID}-${TIMESTAMP}"
          AZ_OPTS="--destination-path ${PIPELINE}/${PIPELINE_TASK}"
        fi
        echo -n $CONTAINER_NAME > /tekton/results/container-name
        {{ if not .Values.noGit }}
        cat /git/qgc-git-info | gzip -c > /evidence/git-info.txt.gz
        {{ end }}
        cp /etc/podinfo/labels /evidence/labels.txt
        LABEL_WHITELIST="qgc/(created-by|namespace|owner|quality-gate|release.*|run-uid)"
        (grep -E "${LABEL_WHITELIST}" /etc/podinfo/labels ; echo ) | while read label
        do
          if [ -z "$label" ]; then continue ; fi
          key=`echo $label | sed 's/=.*//'`
          value=`echo $label | sed "s|$key\=||" | xargs echo | sed 's/ /\\ /g'`
          key=`echo ${key} | sed "s/[\./\-]/_/g"`
          echo -n "$key=$value " >> /tmp/metadata
        done
        # Retrieving pod annotations and store it with evidences + sha256 in metadata
        cat /etc/podinfo/annotations | gzip -c > /evidence/task-annotations.gz
        # create container in Azure Blob
        az storage container create --name "$CONTAINER_NAME"
        # Retrieve logs
        python3 /xunit-analyzer/download-logs.py --skip step-upload-evidences step-check-for-defects
        # upload evidences
        az storage blob upload-batch --source /evidence -d "$CONTAINER_NAME" ${AZ_OPTS}
        # Set metadata
        az storage container metadata update --name "$CONTAINER_NAME" --metadata `cat /tmp/metadata`
        # done
- name: check-for-defects
  image: {{ .Values.global.image.azure.repository }}:{{ .Values.global.image.azure.tag }}
  script: |-
{{- if not .Values.disableParseXunit }}
    # parse [XJ]unit file
    python3 /xunit-analyzer/xunit-parser.py -i /evidence -o /tekton/results
{{- end }}
    # Updating annotations with parsed values
    bash /xunit-analyzer/update-task-run-annotations.sh
    # Check assertions on it
    python3 /xunit-analyzer/check-assertions.py -r /tekton/results --assertion $(params.threshold) $THRESHOLD
{{- end }}
{{ end }}

{{ define "tasks.defaultResults" -}}
- name: tests
  description: Tests count
- name: errors
  description: Errors count
- name: failures
  description: Failures count
- name: skipped
  description: Skipped tests count
- name: disabled
  description: Disabled tests count
{{- end }}

{{ define "tasks.specificResults" -}}
{{ if .Values.specificResults -}}
{{   toYaml .Values.specificResults }}
{{- end }}
{{- end }}

{{ define "tasks.persistentVolumClaim" }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "tasks.fullname" . }}
  labels:
    {{- include "tasks.labels" . | nindent 4 }}
spec:
  {{- toYaml .Values.persistentVolumeClaim | nindent 2 }}
{{ end }}

{{ define "tasks.definition" }}
{{ if .Values.persistentVolumeClaim }}
---
{{ include "tasks.persistentVolumClaim" . }}
{{ end }}
---
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: {{ include "tasks.fullname" . }}
  labels:
    {{- include "tasks.labels" . | nindent 4 }}
    qgc/type: {{ .Values.type }}
    qgc/kind: {{ .Values.kind }}
  annotations:
    {{ if not .Values.noEvidence }}qgc.params.kind/threshold: "threshold"{{ end }}
    {{- if .Values.global.annotations }}{{- .Values.global.annotations | toYaml | nindent 4 }}{{ end }}
    {{- .Values.global.tasks.annotations | toYaml | nindent 4 }}
spec:
  description: "{{ .Chart.Description }}"
  params:
    {{- if not .Values.noEvidence }}
    - name: threshold
      default: "defects=0%"
      description: "Defects threshold"
    {{- end }}
    {{- include "tasks.envParameters" . | nindent 4 -}}
    {{ if not .Values.noGit }}{{ include "tasks.gitRepos" . | nindent 4 }}{{ end }}
    {{- if .Values.params }}{{- toYaml .Values.params | nindent 4 }}{{- end }}
  results:
    - name: container-name
      description: Azure Blob container name
    {{- include "tasks.defaultResults" . | nindent 4 }}
    {{- include "tasks.specificResults" . | nindent 4 }}
  stepTemplate:
    image: "{{ include "tasks.imageUrl" . }}"
    volumeMounts:
      {{ if not .Values.noGit }}
      - name: git
        mountPath: /git
      {{ end }}
      {{- if not .Values.noEvidence }}
      - name: evidence
        mountPath: /evidence
      {{- end }}
      - name: xunit-analyzer
        mountPath: /xunit-analyzer
      {{- if .Values.volumeMounts }}{{- toYaml .Values.volumeMounts | nindent 6 }}{{ end }}
    {{ if not .Values.noGit }}
    workingDir: "/git"
    {{ end }}
    envFrom:
      {{- include "tasks.loadEnvParameters" . | nindent 6 }}
    env:
      {{- if .Values.env }}
      {{- toYaml .Values.env | nindent 6 }}
      {{- end }}
      {{- if not .Values.noEnv }}
      - name: "TASK_RUN"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['tekton.dev/taskRun']
      - name: "NAMESPACE"
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: "PIPELINE"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['tekton.dev/pipeline']
      - name: "PIPELINE_TASK"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['tekton.dev/pipelineTask']
      - name: "RELEASE_UID"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['qgc/release-uid']
      - name: "QUALITY_GATE"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['qgc/quality-gate']
      - name: "RELEASE_NAME"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['qgc/release-name']
      - name: "TIMESTAMP"
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['qgc/release-timestamp']
      - name: "RELEASE_DATE"
        valueFrom:
          fieldRef:
            fieldPath: metadata.annotations['qgc/release-date']
      - name: THRESHOLD
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['qgc/threshold']
      - name: UID
        valueFrom:
          fieldRef:
            fieldPath: metadata.uid
      {{- end }}
  volumes:
    {{- if not .Values.noEvidence }}
    - name: evidence
      emptyDir: {}
    {{- end }}
    {{ if not .Values.noGit }}
    - name: git
      emptyDir: {}
    {{ end }}
    - name: podinfo
      downwardAPI:
        items:
          - path: "labels"
            fieldRef:
              fieldPath: metadata.labels
          - path: "annotations"
            fieldRef:
              fieldPath: metadata.annotations
    - name: xunit-analyzer
      configMap:
        name: "{{ .Release.Name }}"
        defaultMode: 0755
    {{- if .Values.volumes }}{{- toYaml .Values.volumes | nindent 4 }}{{ end }}
  steps:
    {{- if not .Values.noGit -}}
    {{- include "task.gitCheckout" . | nindent 4 }}
    {{- end }}
    {{ toYaml .Values.steps | nindent 4 }}
    {{ include "task.uploadEvidences" . | nindent 4 }}

{{ end }}

{{- define "tasks.proxyUrl" -}}
{{-   if .Values.global.proxy.enabled -}}
{{-     with .Values.global.proxy -}}{{ .protocol }}://{{ .host }}:{{ .port }}{{- end -}}
{{-   end -}}
{{- end -}}
