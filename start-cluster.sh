#!/bin/bash

INGRESS_HOST=127.0.0.1.nip.io

# start kind cluster with 3 nodes
kind create cluster --config=cluster.yaml

# install ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=3m0s

## install argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install \
  argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  --set server.ingress.hosts="{argo-cd.$INGRESS_HOST}" \
  --values argocd/helm-values.yaml \
  --timeout 6m0s \
  --wait

## install kubevela
helm repo add kubevela https://charts.kubevela.net/core
helm repo update
helm upgrade --install \
  kubevela kubevela/vela-core \
  -n vela-system \
  --create-namespace \
  --version 1.4.1 \
  --wait

kubectl apply -f kubevela/argocd-trait.yaml -n vela-system

## install crossplane
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

## install backstage
kubectl create namespace backstage

rm backstage.env

echo "POSTGRES_HOST=backstage-db" >> backstage.env
echo "POSTGRES_PORT=5432" >> backstage.env
echo "AUTH_GITHUB_CLIENT_ID=$AUTH_GITHUB_CLIENT_ID" >> backstage.env
echo "AUTH_GITHUB_CLIENT_SECRET=$AUTH_GITHUB_CLIENT_SECRET" >> backstage.env

## Generate token for backstage
echo "Generate token for backstage"
argocd login argo-cd.${INGRESS_HOST} --name local --username admin --password admin --insecure --grpc-web-root-path /
AUTH_TOKEN=$(yq eval '.users[0].auth-token' ~/.config/argocd/config)
argocd account generate-token --account backstage --id backstage --auth-token ${AUTH_TOKEN} | sed -e 's/^/ARGOCD_AUTH_TOKEN=/' >> backstage.env

kubectl create secret generic backstage -n backstage --from-env-file=backstage.env

rm backstage.env

kubectl create secret generic backstage-github-file -n backstage --from-file=github-credentials.yaml=./github-credentials.yaml

sed "s/BASE_DOMAIN_VALUE/${INGRESS_HOST}/g" backstage/app.yaml | kubectl apply -f -

kubectl wait --namespace backstage \
  --for=condition=ready pod \
  --selector=app=backstage \
  --timeout=3m0s

## Deploy Apps in ArgoCD
kubectl apply -f https://raw.githubusercontent.com/devops-syndicate/argocd-apps/main/applicationset.yaml -n argocd
kubectl apply -f https://raw.githubusercontent.com/devops-syndicate/infrastructure/main/applicationset.yaml -n argocd