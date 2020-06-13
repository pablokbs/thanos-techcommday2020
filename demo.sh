#!/usr/bin/env bash

. setup.sh --source-only
. demo-nav.sh

clear


# set -x
# We assume ./setup.sh was successfully ran.

# Some yolo aliases (without using `alias`)

# Double Esc or Ctrl+Q to close it.
#function open() {
#    # Image viewer on fullscreen.
#    eog -wgf "$@"
#}
#function cat() {
#    bat -p "$@"
#}

MINIO_ACCESS_KEY="smth"
MINIO_SECRET_KEY="Need8Chars"
HOST_IP=

# Grafana only!

#rc "open slides/1-title.svg" # Slide to 2) improbable
r "kubectl --context=eu1 get po"
r "kubectl --context=us1 get po"

# Need ctrl+w to close and fullscreen beforehand!
# Ignore: ro "open \$(minikube -p eu1 service prometheus --url)/graph" "google-chrome --app=\"`minikube -p eu1 service prometheus --url`/graph?g0.range_input=1d&g0.expr=sum(container_memory_usage_bytes)%20by%20(pod%2C%20cluster)&g0.tab=0\" > /dev/null"
# Ignore for now: ro "open \$(minikube -p eu1 service alertmanager --url)" "google-chrome --app=`minikube -p eu1 service alertmanager --url` > /dev/null"
#r "echo \$(minikube -p eu1 service grafana --url)" "google-chrome --app=\"`minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1\" > /dev/null
r "Veamos un grafico de memoria en Grafana y hablemos de Global view" "echo `minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1"
# Problems shown in grafana: global view.

# Explain HA.
r "Poca disponibilidad | kubectl --context=eu1 get po" "kubectl --context=eu1 get po"
r "Solo 1 pod de prometheus por cluster | kubectl --context=us1 get po" "kubectl --context=us1 get po"

# Add naive HA.
r "Generemos 6h de metricas: applyPersistentVolumeWithGeneratedMetrics eu1 1 6h" "applyPersistentVolumeWithGeneratedMetrics eu1 1 6h"
r "Modifiquemos nuestros prometheus.yaml para agregar mas replicas" "colordiff -y manifests/prometheus.yaml manifests/prometheus-ha.yaml"
r "kubectl --context=eu1 apply -f manifests/prometheus-ha.yaml" "cat manifests/prometheus-ha.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\" |tail -n1`#g\" | sed \"s#%%CLUSTER%%#eu1#g\" | kubectl --context=eu1 apply -f -"
r "kubectl --context=eu1 get po"

r "Agreguemos el nuevo datasource a Grafana" "colordiff -y manifests/grafana-datasources.yaml manifests/grafana-ha-datasources.yaml "
r "Apliquemos el manifiesto de Grafana | kubectl --context=eu1 apply -f manifests/grafana-ha-datasources.yaml" "sed \"s#%%PROM_US1_URL%%#$(minikube -p us1 service prometheus --url)#g\" manifests/grafana-ha-datasources.yaml | kubectl apply -f - && kubectl --context=eu1 delete po \$(kubectl --context=eu1 get po -l app=grafana -o jsonpath={.items..metadata.name})"
r "kubectl --context=eu1 get po"
#r "echo \$(minikube -p eu1 service grafana --url)" "google-chrome --app=\"`minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1\" > /dev/null"
r "Veamos ahora nuestro multi-replica con Grafana, la retención y problemas de downsampling" "echo `minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1"

# Retention problem shown on prom-1 range.

# FIRST STEP: Sidecar.
r "PASO 1: Tratemos de combinar las métricas, agregando un sidecar de Thanos" "colordiff -y manifests/prometheus-ha.yaml manifests/prometheus-ha-sidecar.yaml "
r "Apliquemos estos cambios en us1 | kubectl --context=eu1 apply -f manifests/prometheus-ha-sidecar.yaml" "cat manifests/prometheus-ha-sidecar.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\"| tail -n1`#g\" | sed \"s#%%CLUSTER%%#eu1#g\" | kubectl --context=eu1 apply -f -"
r "Creemos 6h de metricas en eu1 y apliquemos los cambios | kubectl --context=us1 apply -f manifests/prometheus-ha-sidecar.yaml" "applyPersistentVolumeWithGeneratedMetrics us1 1 336h && cat manifests/prometheus-ha-sidecar.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\"| tail -n1`#g\" | sed \"s#%%CLUSTER%%#us1#g\" | kubectl --context=us1 apply -f -"
r "kubectl --context=eu1 get po"
r "kubectl --context=us1 get po"

# SECOND step: querier
r "PASO 2: Agreguemos thanos-querier | cat manifests/thanos-querier.yaml"
r "Apliquemos thanos-querier | kubectl --context=eu1 apply -f manifests/thanos-querier.yaml" "cat manifests/thanos-querier.yaml | sed \"s#%%SIDECAR_US1_0_URL%%#\$(minikube -p us1 service sidecar --format=\"{{.IP}}:{{.Port}}\"|tail -n1)#g\" |  sed \"s#%%SIDECAR_US1_1_URL%%#\$(minikube -p us1 service sidecar-1 --format=\"{{.IP}}:{{.Port}}\" |tail -n1)#g\" | kubectl --context=eu1 apply -f -"
r "kubectl --context=eu1 get po"
# Show on artifical data!
#r "echo \$(minikube -p eu1 service thanos-querier --url)/graph" "google-chrome --app=\"\$(minikube -p eu1 service thanos-querier --url)/graph?g0.range_input=2h&g0.expr=avg(container_memory_usage_bytes)%20by%20(cluster,replica)&g0.tab=0\" > /dev/null"
r "Veamos la interfaz de Thanos Query" "echo `minikube -p eu1 service thanos-querier --url`/graph?g0.range_input=2h\&g0.expr=avg\(container_memory_usage_bytes\)%20by%20\(cluster,replica\)\&g0.tab=0"

# THIRD: Connect grafana to querier
r "PASO 3: Conectemos Grafana a Thanos Query" "colordiff -y manifests/grafana-ha-datasources.yaml manifests/grafana-datasources-querier.yaml"
r "Apliquemos el manifiesto | kubectl --context=eu1 apply -f manifests/grafana-datasources-querier.yaml" "kubectl --context=eu1 apply -f manifests/grafana-datasources-querier.yaml && kubectl --context=eu1 delete po \$(kubectl --context=eu1 get po -l app=grafana -o jsonpath={.items..metadata.name})"
r "kubectl --context=eu1 get po"
#r "echo \$(minikube -p eu1 service grafana --url)" "google-chrome --app=\"`minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1\" > /dev/null"
r "Veamos Grafana con global view" "echo `minikube -p eu1 service grafana --url`/d/pods_memory/pods-memory?orgId=1"

# Show removal of cluster label on grafana - GV and HA done.

# Put yolo local object storage.
r "Veamos si podemos tener storage ilimitado, deployemos minio | kubectl --context=eu1 apply -f manifests/minio.yaml" "kubectl --context=eu1 apply -f manifests/minio.yaml"
r "kubectl --context=eu1 get po"
r "Creemos un bucket con minio" "mc config host add minio \$(minikube -p eu1 service minio --url) smth Need8Chars --api S3v4 && mc mb minio/demo-bucket"

# FOURTH STEP: Sidecar upload.
r "PASO 4: Deployemos el sidecar para storage de Thanos" "colordiff -y manifests/prometheus-ha-sidecar.yaml manifests/prometheus-ha-sidecar-lts.yaml "
r "Apliquemos el manifiesto en eu1 | kubectl --context=eu1 apply -f manifests/prometheus-ha-sidecar-lts.yaml" "cat manifests/prometheus-ha-sidecar-lts.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\" |tail -n1`#g\" | sed \"s#%%CLUSTER%%#eu1#g\" | sed \"s#%%S3_ENDPOINT%%#\$(minikube -p eu1 service minio --format=\"{{.IP}}:{{.Port}}\" |tail -n1)#g\" | kubectl --context=eu1 apply -f -"
r "Apliquemos el manifiesto en us1 | kubectl --context=us1 apply -f manifests/prometheus-ha-sidecar-lts.yaml" "cat manifests/prometheus-ha-sidecar-lts.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\" | tail -n1`#g\" | sed \"s#%%CLUSTER%%#us1#g\" | sed \"s#%%S3_ENDPOINT%%#\$(minikube -p eu1 service minio --format=\"{{.IP}}:{{.Port}}\"|tail -n1)#g\" | kubectl --context=us1 apply -f -"
r "kubectl --context=eu1 get po"
r "kubectl --context=us1 get po"

# Show if upload works.
r "Veamos si thanos ya subio las metricas al bucket" "mc ls minio/demo-bucket"
r "mc ls minio/demo-bucket/`mc ls minio/demo-bucket/ | sed '1q' | cut -d ' ' -f 10`"

# FIFTH: compactor
r "PASO 5: Agreguemos el compactor | kubectl --context=eu1 apply -f manifests/thanos-compactor.yaml" "cat manifests/thanos-compactor.yaml | sed \"s#%%S3_ENDPOINT%%#\$(minikube -p eu1 service minio --format=\"{{.IP}}:{{.Port}}\"|tail -n1)#g\" | kubectl --context=eu1 apply -f -"
r "kubectl --context=eu1 get po"

# SIXTH: gateway
r "PASO 6: Agreguemos el gateway, que va a mostrar las metricas del bucket" "cat manifests/thanos-store-gateway.yaml"
r "kubectl --context=eu1 apply -f manifests/thanos-store-gateway.yaml" "cat manifests/thanos-store-gateway.yaml | sed \"s#%%S3_ENDPOINT%%#\$(minikube -p eu1 service minio --format=\"{{.IP}}:{{.Port}}\"|tail -n1)#g\" | kubectl --context=eu1 apply -f -"
r "kubectl --context=eu1 get po"

# How to make sure we can see store gateway? Simulate outage (no connection?) to us1 cluster!

r "Probemos si thanos-gateway funciona, matemos Prometheus! | kubectl --context=us1 delete statefulset prometheus" "kubectl --context=us1 delete statefulset prometheus"
r "kubectl --context=us1 get po"
# We should see only uploaded data from us1, but no straight connection.
#r "echo \$(minikube -p eu1 service thanos-querier --url)/graph" "google-chrome --app=\"\$(minikube -p eu1 service thanos-querier --url)/graph?g0.range_input=2h&g0.expr=avg(container_memory_usage_bytes)%20by%20(cluster,replica)&g0.tab=0\" > /dev/null"
r "Veamos thanos-query, deberiamos ver datos pero no conexión" "echo `minikube -p eu1 service thanos-querier --url`/graph\?g0.range_input=6h\&g0.expr=avg\(container_memory_usage_bytes\)%20by%20\(cluster,replica\)\&g0.tab=0"

# Show that outage is UNNOTICED!
#r "echo \$(minikube -p eu1 service alertmanager --url)" "google-chrome --app=`minikube -p eu1 service alertmanager --url` > /dev/null"
r "PROBLEMA: Alertmanager no avisa!" "echo `minikube -p eu1 service alertmanager --url`"

# Step number SEVEN: ruler
r "PASO 7: Meta-monitoreo con thanos-ruler | cat manifests/thanos-ruler.yaml" "cat manifests/thanos-ruler.yaml"
r "kubectl --context=eu1 apply -f manifests/thanos-ruler.yaml" "cat manifests/thanos-ruler.yaml | sed \"s#%%ALERTMANAGER_URL%%#`minikube -p eu1 service alertmanager --format=\"{{.IP}}:{{.Port}}\"|tail -n1`#g\" | sed \"s#%%CLUSTER%%#eu1#g\" | sed \"s#%%S3_ENDPOINT%%#\$(minikube -p eu1 service minio --format=\"{{.IP}}:{{.Port}}\"|tail -n1)#g\" | kubectl --context=eu1 apply -f -"
r "kubectl --context=eu1 get po"
#r "echo \$(minikube -p eu1 service thanos-ruler --url)/graph" "google-chrome --app=\"\$(minikube -p eu1 service thanos-ruler --url)\" > /dev/null"
r "Veamos la UI de Thanos ruler" "echo `minikube -p eu1 service thanos-ruler --url`"

# Show outage is at least noticed.
#r "echo \$(minikube -p eu1 service alertmanager --url)" "google-chrome --app=`minikube -p eu1 service alertmanager --url` > /dev/null"
r "Ahora veamos AlertManager..." "echo `minikube -p eu1 service alertmanager --url`"

# The end.
#rc "open slides/7-the-end.svg"
rc "Arquitectura en producción" "echo https://docs.google.com/presentation/d/1ya3WwVYFhM8E-N_U2F252GIhOwvHbEw8Y8_qHxZ2Q1M/edit#slide=id.g88c4ffbf14_0_0"

navigate true
