kind_base_domain := '127.0.0.1.nip.io'
argocd_version := '5.14.1'
kubevela_version := '1.6.3'
prometheus_version := '18.0.0'
grafana_version := '2.7.10'
loki_version := '2.8.7'
tempo_version := '0.16.6'
crossplane_version := '1.10.1'
kyverno_version := '2.6.2'
metacontroller_version := 'v4.7.1'
cilium_version := 'v1.12.4'

_default:
  @just -l

## Starts KIND cluster and installs all apps
up:
  just stop_kind
  just start_kind
  just cilium
  just nginx
  just prometheus
  just grafana
  just loki
  just tempo
  just argocd
  just kubevela
  just crossplane
  just backstage

# Stops KIND cluster
down:
  just stop_kind

# Stops KIND cluster
stop_kind:
  kind delete cluster --name k8s-demo

# Starts KIND cluster
start_kind:
  kind create cluster --name k8s-demo --config=cluster.yaml

# Installs cilium
cilium:
  helm repo add cilium https://helm.cilium.io/
  helm repo update
  helm upgrade --install \
    cilium cilium/cilium \
    -n kube-system \
    --set nodeinit.enabled=true \
    --set kubeProxyReplacement=partial \
    --set hostServices.enabled=false \
    --set externalIPs.enabled=true \
    --set nodePort.enabled=true \
    --set hostPort.enabled=true \
    --set ipam.mode=kubernetes \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --version {{cilium_version}} \
    --timeout 6m0s \
    --wait

# Installs metacontroller
metacontroller:
  helm pull oci://ghcr.io/metacontroller/metacontroller-helm --version={{metacontroller_version}}
  helm upgrade --install metacontroller ./metacontroller-helm-{{metacontroller_version}}.tgz \
    -n metacontroller \
    --create-namespace \
    --set fullnameOverride=metacontroller
  rm ./metacontroller-helm-{{metacontroller_version}}.tgz

# Installs kyverno
kyverno:
  helm repo add kyverno https://kyverno.github.io/kyverno/
  helm repo update
  helm upgrade --install \
    kyverno kyverno/kyverno \
    -n kyverno \
    --create-namespace \
    --version {{kyverno_version}}

# Installs ArgoCD
argocd base_host=kind_base_domain:
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install \
    argocd argo/argo-cd \
    -n argocd \
    --create-namespace \
    --version {{argocd_version}} \
    --set server.ingress.hosts="{argo-cd.{{base_host}}}" \
    --values argocd/helm-values.yaml \
    --timeout 6m0s \
    --wait
  kubectl apply -n argocd -f https://raw.githubusercontent.com/devops-syndicate/argocd-apps/main/applicationset.yaml
  kubectl apply -n argocd -f https://raw.githubusercontent.com/devops-syndicate/infrastructure/main/applicationset.yaml

# Installs Kubevela
kubevela:
  helm repo add kubevela https://charts.kubevela.net/core
  helm repo update
  helm upgrade --install \
    kubevela kubevela/vela-core \
    -n vela-system \
    --create-namespace \
    --version {{kubevela_version}}

# Installs NGINX Ingress Controller
nginx:
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Installs Prometheus
prometheus:
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    prometheus prometheus-community/prometheus \
    -n prometheus \
    --create-namespace \
    --version {{prometheus_version}}

# Installs Loki
loki:
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    loki grafana/loki-stack \
    -n loki \
    --create-namespace \
    --version {{loki_version}}

# Installs Tempo
tempo:
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    tempo grafana/tempo \
    -n tempo \
    --create-namespace \
    --set "tempo.searchEnabled=true" \
    --version {{tempo_version}}

# Installs Crossplane
crossplane:
  #!/usr/bin/env bash
  set -euxo pipefail
  helm repo add crossplane-stable https://charts.crossplane.io/stable
  helm repo update

  helm upgrade --install \
    crossplane crossplane-stable/crossplane \
    -n crossplane-system \
    --create-namespace \
    --version {{crossplane_version}} \
    --set "provider.packages={crossplane/provider-aws:master,crossplane/provider-helm:master}" \
    --wait

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-aws \
      --timeout=3m0s && break
    sleep 10
  done

  ## Create AWS credential secrets for AWS crossplane provider
  AWS_PROFILE=default && echo "[default]
  aws_access_key_id=$(aws configure get aws_access_key_id --profile $AWS_PROFILE)
  aws_secret_access_key=$(aws configure get aws_secret_access_key --profile $AWS_PROFILE)" > creds.conf

  kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=./creds.conf
  rm creds.conf

  kubectl wait --for condition=established --timeout=60s crd/compositeresourcedefinitions.apiextensions.crossplane.io crd/compositions.apiextensions.crossplane.io crd/providerconfigs.aws.crossplane.io

  ## Configure AWS Crossplane Provider
  kubectl apply -n crossplane-system -f crossplane/package.yaml
  kubectl apply -n crossplane-system -f crossplane/provider-config.yaml

## Installs Grafana
grafana base_host=kind_base_domain: nginx
  #!/usr/bin/env bash
  kubectl create namespace grafana-operator
  rm grafana.env
  echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> grafana.env
  echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> grafana.env
  echo "GF_AUTH_GITHUB_ROLE_ATTRIBUTE_PATH=contains(groups[*], '@devops-syndicate/admins') && 'Admin' || 'Editor'" >> grafana.env

  kubectl create secret generic grafana -n grafana-operator --from-env-file=grafana.env

  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
  helm upgrade --install \
    grafana-operator bitnami/grafana-operator \
    -n grafana-operator \
    --create-namespace \
    --set grafana.ingress.hostname="grafana.{{base_host}}" \
    --set grafana.config.server.root_url="https://grafana.{{base_host}}" \
    --values grafana-operator/helm-values.yaml \
    --version {{grafana_version}} \
    --wait
  while : ; do
    kubectl rollout -n grafana-operator status deployment grafana-deployment && break
    sleep 2
  done
  kubectl apply -f grafana-operator/prometheus-datasource.yaml
  kubectl apply -f grafana-operator/loki-datasource.yaml
  kubectl apply -f grafana-operator/tempo-datasource.yaml

# Installs Backstage
backstage base_host=kind_base_domain:
  #!/usr/bin/env bash
  kubectl create namespace backstage
  rm backstage.env
  echo "POSTGRES_HOST=backstage-db" >> backstage.env
  echo "POSTGRES_PORT=5432" >> backstage.env
  echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> backstage.env
  echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> backstage.env

  echo "Generate token for backstage"
  argocd login argo-cd.{{base_host}} --name local --username admin --password admin --insecure --grpc-web-root-path /
  AUTH_TOKEN=$(yq eval '.users[0].auth-token' ~/.config/argocd/config)
  argocd account generate-token --account backstage --id backstage --auth-token ${AUTH_TOKEN} | sed -e 's/^/ARGOCD_AUTH_TOKEN=/' >> backstage.env

  kubectl create secret generic backstage -n backstage --from-env-file=backstage.env

  rm backstage.env

  kubectl create secret generic backstage-github-file -n backstage --from-file=github-credentials.yaml=./github-credentials.yaml

  sed "s/BASE_DOMAIN_VALUE/{{base_host}}/g" backstage/app.yaml | kubectl apply -f -

  kubectl wait -n backstage \
    --for=condition=ready pod \
    --selector=app=backstage