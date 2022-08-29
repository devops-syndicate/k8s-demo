kind_base_domain := '127.0.0.1.nip.io'

_default:
  @just -l

## Starts KIND cluster and installs all apps
up:
  just stop_kind
  just start_kind
  just nginx
  just prometheus
  just grafana
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

# Installs ArgoCD
argocd base_host=kind_base_domain:
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install \
    argocd argo/argo-cd \
    -n argocd \
    --create-namespace \
    --set server.ingress.hosts="{argo-cd.{{base_host}}}" \
    --values argocd/helm-values.yaml \
    --timeout 6m0s \
    --wait

# Installs Kubevela
kubevela:
  helm repo add kubevela https://charts.kubevela.net/core
  helm repo update
  helm upgrade --install \
    kubevela kubevela/vela-core \
    -n vela-system \
    --create-namespace \
    --version 1.5.3 \
    --wait
  kubectl apply -f kubevela/argocd-trait.yaml -n vela-system

# Installs NGINX Ingress Controller
nginx:
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=3m0s

# Installs Prometheus
prometheus:
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    prometheus prometheus-community/prometheus \
    -n prometheus \
    --create-namespace \
    --version 15.12.0 \
    --wait

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
    --set "provider.packages={crossplane/provider-aws:master,crossplane/provider-helm:master}" \
    --wait

  while : ; do
    kubectl wait --namespace crossplane-system \
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
    --version 2.6.11 \
    --wait
  while : ; do
    kubectl rollout --namespace grafana-operator status deployment grafana-deployment && break
    sleep 2
  done
  kubectl apply -f grafana-operator/datasource.yaml

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

  kubectl wait --namespace backstage \
    --for=condition=ready pod \
    --selector=app=backstage \
    --timeout=3m0s