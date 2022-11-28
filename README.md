# Local k8s cluster setup with ArgoCD, Crossplane, Kubevela and Linkerd

## Prerequisites

*Tools*

- kind
- kubectl
- helm
- aws CLI
- argocd CLI

*AWS Setup*

To use the AWS Provider the AWS cli has to be setup locally already with `ACCESS_KEY_ID` and `SECRET_ACESS_KEY`.

## Setup

Run `just up`. After the setup run through, you can access argocd:

- URL: argo-cd.127.0.0.1.nip.io
- username: admin
- password: admin

## Backstage Add-On

To install backstage, you have to setup in github a