#!/bin/bash
set -eou pipefail

GOPATH=$(go env GOPATH)
REPO_ROOT=$GOPATH/src/github.com/kubedb/service-broker

export DOCKER_REGISTRY=shudipta
export IMG=service-broker
export TAG=latest
export ONESSL=

export NAME=service-broker
export NAMESPACE=service-broker
export SERVICE_ACCOUNT="$NAME"
export APP=service-broker
export IMAGE_PULL_POLICY=IfNotPresent
export IMAGE_PULL_SECRET=

export KUBEDB_ENV=${KUBEDB_ENV:-prod}
export SCRIPT_LOCATION="curl -fsSL https://raw.githubusercontent.com/kubedb/service-broker/master/"
if [ "$KUBEDB_ENV" = "dev" ]; then
    export SCRIPT_LOCATION="cat "
    export TAG=$TAG
    export IMAGE_PULL_POLICY=Always
fi

export CMD=

show_help() {
    echo "build.sh"
    echo " "
    echo "build.sh [commands] [options]"
    echo " "
    echo "commands:"
    echo "---------"
    echo "build         builds and push the docker image for service-broker"
    echo "run           installs service-broker"
    echo "uninstall     uninstalls service-broker"
    echo " "
    echo "options:"
    echo "--------"
    echo "-h, --help                    show brief help"
    echo "-n, --namespace=NAMESPACE     specify namespace (default: $NAMESPACE)"
    echo "    --docker-registry         docker registry used to pull stash images (default: $DOCKER_REGISTRY)"
    echo "    --image-pull-secret       name of secret used to pull service broker image"
}

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        build|run|uninstall)
            export CMD=$1
            shift
            ;;
        -n)
            shift
            if test $# -gt 0; then
                export NAMESPACE=$1
            else
                echo "no namespace specified"
                exit 1
            fi
            shift
            ;;
        --namespace*)
            export NAMESPACE=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --docker-registry*)
            export DOCKER_REGISTRY=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --image-pull-secret*)
            secret=`echo $1 | sed -e 's/^[^=]*=//g'`
            export IMAGE_PULL_SECRET="name: '$secret'"
            shift
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

echo "DOCKER_REGISTRY=$DOCKER_REGISTRY"
echo "IMG=$IMG"
echo "TAG=$TAG"
echo "ONESSL=$ONESSL"
echo "NAME=$NAME"
echo "NAMESPACE=$NAMESPACE"
echo "SERVICE_ACCOUNT=$SERVICE_ACCOUNT"
echo "APP=$APP"
echo "IMAGE_PULL_POLICY=$IMAGE_PULL_POLICY"
echo "IMAGE_PULL_SECRET=$IMAGE_PULL_SECRET"
echo ""
echo "KUBEDB_ENV=$KUBEDB_ENV"
echo "SCRIPT_LOCATION=$SCRIPT_LOCATION"
echo ""

build() {
    pushd $REPO_ROOT
        mkdir -p hack/docker
        go build -o hack/docker/service-broker cmd/servicebroker/main.go
#        cp hack/dev/kubedb.sh hack/docker/kubedb.sh

        pushd hack/docker
            chmod 755 service-broker
            cat > Dockerfile <<EOL
FROM ubuntu

COPY service-broker /bin/service-broker
EOL
            local cmd="docker build -t $DOCKER_REGISTRY/$IMG:$TAG ."
            echo $cmd; $cmd
            cmd="docker push $DOCKER_REGISTRY/$IMG:$TAG"
            echo $cmd; $cmd
        popd

        rm -rf hack/docker
    popd
}

ensure_onessl() {
    if [ -x "$(command -v onessl)" ]; then
        export ONESSL=onessl
    else
        # ref: https://stackoverflow.com/a/27776822/244009
        case "$(uname -s)" in
            Linux)
                curl -fsSL -o onessl https://github.com/kubepack/onessl/releases/download/0.3.0/onessl-linux-amd64
                chmod +x onessl
                export ONESSL=./onessl
                ;;

            *)
                echo 'other OS'
                ;;
        esac
    fi
}

deploy_service_broker() {
    local found=0
    ns=($(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name} {end}'))
    for n in "${ns[@]}"; do
        if [ "$n" = "$NAMESPACE" ]; then
            export found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        kubectl create ns $NAMESPACE
    fi

    ${SCRIPT_LOCATION}hack/deploy/deployment.yaml | $ONESSL envsubst | kubectl apply -f -
    ${SCRIPT_LOCATION}hack/deploy/service.yaml | $ONESSL envsubst | kubectl apply -f -
    ${SCRIPT_LOCATION}hack/deploy/rbac.yaml | $ONESSL envsubst | kubectl apply -f -
    ${SCRIPT_LOCATION}hack/deploy/cluster_service_broker.yaml | $ONESSL envsubst | kubectl apply -f -

    echo
    echo "waiting until service-broker deployment is ready"
    $ONESSL wait-until-ready deployment $NAME --namespace $NAMESPACE || { echo "service-broker deployment failed to be ready"; exit 1; }

    echo
    echo "Successfully installed service-broker in $NAMESPACE namespace!"
}

run() {
    pushd $REPO_ROOT
        ensure_onessl
        deploy_service_broker
    popd
}

uninstall() {
    # delete service-broker
    kubectl delete service -l app=$APP --namespace $NAMESPACE
    kubectl delete deployment -l app=$APP --namespace $NAMESPACE
    # delete RBAC objects, if --rbac flag was used.
    kubectl delete serviceaccount -l app=$APP --namespace $NAMESPACE
    kubectl delete clusterrolebindings -l app=$APP

    echo
    echo "waiting for service-broker pod to stop running"
    for (( ; ; )); do
        pods=($(kubectl get pods --all-namespaces -l app=$APP -o jsonpath='{range .items[*]}{.metadata.name} {end}'))
        total=${#pods[*]}
        if [ $total -eq 0 ] ; then
            break
        fi
        sleep 2
    done

    kubectl delete clusterservicebroker -l app=$APP
    kubectl delete ns $NAMESPACE

    echo
    echo "Successfully uninstalled service-broker!"
    exit 0
}

$CMD

"$@"