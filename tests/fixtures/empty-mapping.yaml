# Empty YAML mapping must parse as a single text node (issue #22).
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: cache
          mountPath: /cache
  volumes:
    - name: cache
      emptyDir: {}
    - name: config
      configMap:
        name: {{ .Values.configMapName | default "app-config" | quote }}
