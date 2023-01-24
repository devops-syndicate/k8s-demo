base_host := '127.0.0.1.nip.io'

cilium_version := 'v1.12.5'
traefik_version := '20.8.0'
argo_rollouts_version := '2.22.1'
metacontroller_version := 'v4.7.3'
kyverno_version := '2.6.5'
kubevela_version := '1.7.0'
pyroscope_version := '0.2.86'
prometheus_version := '19.3.1'
loki_version := '2.8.9'
tempo_version := '0.16.9'
grafana_version := '6.50.1'
argocd_version := '5.19.0'
crossplane_version := '1.10.2'

_default:
  @just -l

## Starts KIND cluster and installs all apps
up:
  just helm_repos
  just stop_kind
  just start_kind
  just ingress
  just rollouts
  just metacontroller
  just kyverno
  just kubevela
  just pyroscope
  just prometheus
  just loki
  just tempo
  just grafana
  just argocd
  just crossplane
  just backstage

# Adds all needed repos to helm
helm_repos:
  helm repo add cilium https://helm.cilium.io/
  helm repo add traefik https://traefik.github.io/charts
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo add kyverno https://kyverno.github.io/kyverno/
  helm repo add kubevela https://charts.kubevela.net/core
  helm repo add pyroscope-io https://pyroscope-io.github.io/helm-chart
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo add crossplane-stable https://charts.crossplane.io/stable
  helm repo update

# Stops KIND cluster
down:
  just stop_kind

# Stops KIND cluster
stop_kind:
  kind delete cluster --name k8s-demo

# Starts KIND cluster
start_kind:
  kind create cluster --name k8s-demo --config=cluster.yaml
  just cilium

# Installs cilium
cilium:
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

# Installs Ingress Controller
ingress:
  helm upgrade --install \
    traefik traefik/traefik \
    -n traefik \
    --create-namespace \
    --set 'ingressRoute.dashboard.matchRule="Host(`traefik.{{base_host}}`\, `localhost`) && PathPrefix(`/dashboard`\, `/api`)"' \
    --values traefik/helm-values.yaml \
    --version {{traefik_version}} \
    --wait

# Installs Argo Rollouts
rollouts:
  helm upgrade --install \
    argocd argo/argo-rollouts \
    -n argo-rollouts \
    --create-namespace \
    --version {{argo_rollouts_version}}

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
  helm upgrade --install \
    kyverno kyverno/kyverno \
    -n kyverno \
    --create-namespace \
    --version {{kyverno_version}}

# Installs Kubevela
kubevela:
  helm upgrade --install \
    kubevela kubevela/vela-core \
    -n vela-system \
    --create-namespace \
    --version {{kubevela_version}}

# Installs pyroscope
pyroscope:
  helm upgrade --install \
    pyroscope pyroscope-io/pyroscope \
    -n pyroscope \
    --create-namespace \
    --set-json ingress.hosts='[{"host":"pyroscope.{{base_host}}","paths":[{"path":"/","pathType":"Prefix"}]}]' \
    --values pyroscope/helm-values.yaml \
    --version {{pyroscope_version}}
  kubectl create ns grafana || true
  kubectl apply -f grafana/pyroscope-datasource.yaml

# Installs Prometheus
prometheus:
  helm upgrade --install \
    prometheus prometheus-community/prometheus \
    -n prometheus \
    --create-namespace \
    --version {{prometheus_version}}
  kubectl create ns grafana || true
  kubectl apply -f grafana/prometheus-datasource.yaml

# Installs Loki
loki:
  helm upgrade --install \
    loki grafana/loki-stack \
    -n loki \
    --create-namespace \
    --version {{loki_version}}
  kubectl create ns grafana || true
  kubectl apply -f grafana/loki-datasource.yaml

# Installs Tempo
tempo:
  helm upgrade --install \
    tempo grafana/tempo \
    -n tempo \
    --create-namespace \
    --set "tempo.searchEnabled=true" \
    --version {{tempo_version}}
  kubectl create ns grafana || true
  kubectl apply -f grafana/tempo-datasource.yaml

## Installs Grafana
grafana:
  #!/usr/bin/env bash
  rm grafana.env
  echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> grafana.env
  echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> grafana.env

  kubectl create ns grafana || true
  kubectl create secret generic grafana-github -n grafana --from-env-file=grafana.env

  helm upgrade --install \
    grafana grafana/grafana \
    -n grafana \
    --create-namespace \
    --set ingress.hosts="{grafana.{{base_host}}}" \
    --set "grafana\.ini".server.root_url="https://grafana.{{base_host}}" \
    --values grafana/helm-values.yaml \
    --version {{grafana_version}} \
    --wait

# Installs ArgoCD
argocd:
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

# Installs Crossplane
crossplane:
  #!/usr/bin/env bash
  set -euxo pipefail

  helm upgrade --install \
    crossplane crossplane-stable/crossplane \
    -n crossplane-system \
    --create-namespace \
    --version {{crossplane_version}} \
    --set "provider.packages={crossplane/provider-aws:v0.32.0,crossplane/provider-helm:v0.11.1,crossplane/provider-kubernetes:v0.4.1}" \
    --wait

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-kubernetes \
      --timeout=3m0s && break
    sleep 20
  done

  ## Configure Kubernetes Crossplane Provider
  KUBERNETES_PROVIDER_SA=$(kubectl -n crossplane-system get sa -o name | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
  kubectl create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${KUBERNETES_PROVIDER_SA}" || true
  kubectl apply -n crossplane-system -f crossplane/kubernetes-provider-config.yaml

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-helm \
      --timeout=3m0s && break
    sleep 20
  done

  ## Configure Helm Crossplane Provider
  HELM_PROVIDER_SA=$(kubectl -n crossplane-system get sa -o name | grep provider-helm | sed -e 's|serviceaccount\/|crossplane-system:|g')
  kubectl create clusterrolebinding provider-helm-admin-binding --clusterrole cluster-admin --serviceaccount="${HELM_PROVIDER_SA}" || true
  kubectl apply -n crossplane-system -f crossplane/helm-provider-config.yaml

  while : ; do
    kubectl wait -n crossplane-system \
      --for=condition=ready pod \
      --selector=pkg.crossplane.io/provider=provider-aws \
      --timeout=3m0s && break
    sleep 20
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
  kubectl apply -n crossplane-system -f crossplane/aws-provider-config.yaml

# Installs Backstage
backstage:
  #!/usr/bin/env bash
  kubectl create ns backstage
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
    --selector=app=backstage \
    --timeout=5m