{{- define "miage-bank.waitForDiscovery" -}}
- name: wait-for-discovery
  image: curlimages/curl:latest
  command:
    - 'sh'
    - '-c'
    - |
      until curl -sf http://{{ include "miage-bank.fullname" . }}-discovery:8761/eureka/status; do
        echo "Waiting for Discovery Service..."
        sleep 5
      done
      echo "Discovery Service is ready!"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
{{- end }}

{{- define "miage-bank.waitForConfigServer" -}}
- name: wait-for-config-server
  image: curlimages/curl:latest
  command:
    - 'sh'
    - '-c'
    - |
      until curl -sf http://{{ include "miage-bank.fullname" . }}-config:8888/actuator/health; do
        echo "Waiting for Config Server..."
        sleep 5
      done
      echo "Config Server is ready!"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
{{- end }}

{{- define "miage-bank.waitForMysql" -}}
- name: wait-for-mysql
  image: curlimages/curl:latest
  command:
    - 'sh'
    - '-c'
    - |
      until curl -sf http://{{ include "miage-bank.fullname" . }}-mysql:3306; do
        echo "Waiting for MySQL..."
        sleep 5
      done
      echo "MySQL is ready!"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
{{- end }}
