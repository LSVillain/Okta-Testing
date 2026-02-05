#!/bin/bash

set -euo pipefail

function function_start() {
    echo
    echo " | Begin.....: ${FUNCNAME[1]}"
}

function function_end() {
    echo " | Finish..: ${FUNCNAME[1]}"
}

function apt_install() {
    function_start

    sudo apt-get update -y
    sudo apt-get install -y "$@"

    function_end
}

function configure_git() {
    function_start

    export GITOPS_REPO_USERNAME="LSVillain"
    export GITOPS_REPO_URL="https://github.com/$%7BGITOPS_REPO_USERNAME%7D/Okta-Testing.git"
    export GITHUB_TOKEN_="$"

    if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
        echo " GitHub token not found at $GITHUB_TOKEN_FILE"
        exit 1
    fi


    export GITOPS_REPO_TOKEN=$(<"$GITHUB_TOKEN_FILE")
    function_end
}

function install_docker() {
    function_start

Install Docker if missing,
    if ! command -v docker &> /dev/null; then
        echo " Installing Docker..."
        sudo apt install -y docker.io
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
    else
        echo " Docker already installed"
    fi

    function_end
}

function install_kubectl() {
    function_start

    # Install kubectl if missing
    if ! command -v kubectl &> /dev/null; then
        echo " Installing kubectl..."

        KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
        KUBECTL_URL="https://dl.k8s.io/release/$%7BKUBECTL_VERSION%7D/bin/linux/amd64/kubectl"

        if [ -z "$KUBECTL_VERSION" ]; then
            echo " Failed to fetch kubectl version from dl.k8s.io"
            exit 1
        fi

        curl -Lo kubectl "$KUBECTL_URL"

        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    else
        echo " kubectl already installed"
    fi

    function_end
}

function install_helm() {
    function_start

    # Install Helm if missing
    if ! command -v helm &> /dev/null; then
        echo " Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    else
        echo " Helm already installed"
    fi

    function_end
}

function install_k3s() {
    function_start

    # Install K3s (with Docker runtime)
    if ! command -v k3s &> /dev/null && ! systemctl is-active --quiet k3s; then
        echo " Installing K3s with Docker support..."
        curl -sfL https://get.k3s.io/ | INSTALL_K3S_EXEC="--docker --disable traefik" sh -
    else
        echo " K3s already running"
    fi

    # Setup kubectl config for local user
    mkdir -p "$HOME/.kube"
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

    function_end
}

function install_argo() {
    function_start

    # Install ArgoCD
    if ! kubectl get ns argocd &> /dev/null; then
        echo " Installing ArgoCD..."
        kubectl create namespace argocd
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    else
        echo " ArgoCD already installed"
    fi

    if [[ -z "$GITOPS_REPO_TOKEN" || -z "$GITOPS_REPO_URL" ]]; then
        echo " GitOps repo credentials not initialized properly"
        return 1
    fi

    kubectl -n argocd patch deployment argocd-server \
        --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

    function_end

}

function install_k9s() {
    function_start

    # Install k9s if missing
    if ! command -v k9s &> /dev/null; then
        echo " Installing k9s..."
        K9S_VERSION=$(curl -sL https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f4)
        curl -Lo k9s.tar.gz "https://github.com/derailed/k9s/releases/download/$%7BK9S_VERSION%7D/k9s_Linux_amd64.tar.gz"
        tar -xzf k9s.tar.gz k9s
        chmod +x k9s
        sudo mv k9s /usr/local/bin/
        rm k9s.tar.gz
    else
        echo " k9s already installed"
    fi

    function_end
}

function install_argo_cli() {
    function_start

    # Install Argo CD CLI if missing
    if ! command -v argocd &> /dev/null; then
        echo " Installing Argo CD CLI..."
        ARGOC_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r .tag_name)

        curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/$%7BARGOC_VERSION%7D/argocd-linux-amd64"
        chmod +x argocd
        sudo mv argocd /usr/local/bin/
    else
        echo " Argo CD CLI already installed"
    fi

    echo " Creating ArgoCD repo credentials secret..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitops-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: ${GITOPS_REPO_URL}
  username: ${GITOPS_REPO_USERNAME}
  password: ${GITOPS_REPO_TOKEN}
EOF

    function_end
}


main() {
    echo " Bootstrapping local GitOps environment..."

    configure_git

    apt_install apt-transport-https ca-certificates curl git gnupg jq net-tools nvidia-docker2 socat software-properties-common lsb-release

    install_argo
    install_k3s
    install_helm
    install_argo_cli

    echo " GitOps environment bootstrapped."
    echo " Run this to access ArgoCD locally:"
    echo
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi