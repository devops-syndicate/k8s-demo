# Local k8s cluster setup with ArgoCD, Crossplane, Kubevela and Linkerd

## Prerequisites

*Tools*

- just (https://just.systems/)
- kind (https://kind.sigs.k8s.io/)
- kubectl (https://kubernetes.io/)
- helm (https://helm.sh/)
- aws CLI (https://aws.amazon.com/cli/)
- argocd CLI (https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/)

*AWS Setup*

To use the AWS Provider the AWS cli has to be setup locally already with `ACCESS_KEY_ID` and `SECRET_ACESS_KEY`.

## Setup

Run `just up`. After the setup run through, you can access argocd:

- URL: argo-cd.127.0.0.1.nip.io
- username: admin
- password: admin

## Backstage Add-On

To install backstage, you have to setup in github a