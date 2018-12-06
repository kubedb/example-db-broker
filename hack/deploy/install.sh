#!/bin/bash
set -eou pipefail

echo "checking kubeconfig context"
kubectl config current-context || {
  echo "Set a context (kubectl use-context <context>) out of the following:"
  echo
  kubectl config get-contexts
  exit 1
}
echo ""

# http://redsymbol.net/articles/bash-exit-traps/
function cleanup() {
  rm -rf ${ONESSL}
}
trap cleanup EXIT

# ref: https://github.com/appscodelabs/libbuild/blob/master/common/lib.sh#L55
inside_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
  inside_git=$?
  if [[ "$inside_git" -ne 0 ]]; then
    echo "Not inside a git repository"
    exit 1
  fi
}

detect_tag() {
  inside_git_repo

  # http://stackoverflow.com/a/1404862/3476121
  git_tag=$(git describe --exact-match --abbrev=0 2>/dev/null || echo '')

  commit_hash=$(git rev-parse --verify HEAD)
  git_branch=$(git rev-parse --abbrev-ref HEAD)
  commit_timestamp=$(git show -s --format=%ct)

  if [[ "$git_tag" != '' ]]; then
    TAG=${git_tag}
    TAG_STRATEGY='git_tag'
  elif [[ "$git_branch" != 'master' ]] && [[ "$git_branch" != 'HEAD' ]] && [[ "$git_branch" != release-* ]]; then
    TAG=${git_branch}
    TAG_STRATEGY='git_branch'
  else
    hash_ver=$(git describe --tags --always --dirty)
    TAG="${hash_ver}"
    TAG_STRATEGY='commit_hash'
  fi

  export TAG
  export TAG_STRATEGY
  export git_tag
  export git_branch
  export commit_hash
  export commit_timestamp
}

onessl_found() {
  # https://stackoverflow.com/a/677212/244009
  if [[ -x "$(command -v onessl)" ]]; then
    onessl wait-until-has -h >/dev/null 2>&1 || {
      # old version of onessl found
      echo "Found outdated onessl"
      return 1
    }
    export ONESSL=onessl
    return 0
  fi
  return 1
}

onessl_found || {
  echo "Downloading onessl ..."
  # ref: https://stackoverflow.com/a/27776822/244009
  case "$(uname -s)" in
    Darwin)
      curl -fsSL -o onessl https://github.com/kubepack/onessl/releases/download/0.9.0/onessl-darwin-amd64
      chmod +x onessl
      export ONESSL=./onessl
      ;;

    Linux)
      curl -fsSL -o onessl https://github.com/kubepack/onessl/releases/download/0.9.0/onessl-linux-amd64
      chmod +x onessl
      export ONESSL=./onessl
      ;;

    CYGWIN* | MINGW32* | MSYS*)
      curl -fsSL -o onessl.exe https://github.com/kubepack/onessl/releases/download/0.9.0/onessl-windows-amd64.exe
      chmod +x onessl.exe
      export ONESSL=./onessl.exe
      ;;
    *)
      echo 'other OS'
      ;;
  esac
}

# ref: https://stackoverflow.com/a/7069755/244009
# ref: https://jonalmeida.com/posts/2013/05/26/different-ways-to-implement-flags-in-bash/
# ref: http://tldp.org/LDP/abs/html/comparison-ops.html

export DOCKER_REGISTRY=${DOCKER_REGISTRY:-appscode}
export IMG=service-broker
export TAG=${TAG:-0.1.0}
export ONESSL=

export NAME=service-broker
export NAMESPACE=service-broker
export SERVICE_ACCOUNT="$NAME"
export APP=service-broker
export IMAGE_PULL_POLICY=IfNotPresent
export IMAGE_PULL_SECRET=
export PORT=8080
export CATALOG_PATH="/etc/config/catalogs"
export CATALOG_NAMES="kubedb"
export STORAGE_CLASS=standard
export UNINSTALL=0

export APPSCODE_ENV=${APPSCODE_ENV:-prod}
export SCRIPT_LOCATION="curl -fsSL https://raw.githubusercontent.com/appscode/service-broker/master/"
if [[ "$APPSCODE_ENV" == "dev" ]]; then
    detect_tag
    export SCRIPT_LOCATION="cat "
    export TAG=${TAG}
    export IMAGE_PULL_POLICY=Always
fi

show_help() {
    echo "install.sh - install service-broker"
    echo " "
    echo "install.sh [options]"
    echo " "
    echo "options:"
    echo "--------"
    echo "-h, --help                    show brief help"
    echo "-n, --namespace=NAMESPACE     specify namespace (default: $NAMESPACE)"
    echo "    --docker-registry         docker registry used to pull service-broker image (default: $DOCKER_REGISTRY)"
    echo "    --tag                     tag for service-broker image"
    echo "    --image-pull-secret       name of secret used to pull service-broker image"
    echo "    --port                    port number at which the broker will expose"
    echo "    --catalogPath             the path of catalogs for different service plans"
    echo "    --catalogNames            comma separated names of the catalogs for different service plans"
    echo "    --storage-class           name of the storage-class for database storage"
    echo "    --uninstall               uninstall service-broker"
}

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
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
        --tag*)
            export TAG=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --image-pull-secret*)
            secret=`echo $1 | sed -e 's/^[^=]*=//g'`
            export IMAGE_PULL_SECRET="name: '$secret'"
            shift
            ;;
        --port*)
            export PORT=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --catalogPath*)
            export CATALOG_PATH=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --catalogNames*)
            export CATALOG_NAMES=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --storage-class*)
            export STORAGE_CLASS=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --uninstall)
          export UNINSTALL=1
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
echo "NAME=$NAME"
echo "NAMESPACE=$NAMESPACE"
echo "SERVICE_ACCOUNT=$SERVICE_ACCOUNT"
echo "APP=$APP"
echo "IMAGE_PULL_POLICY=$IMAGE_PULL_POLICY"
echo "IMAGE_PULL_SECRET=$IMAGE_PULL_SECRET"
echo "PORT=$PORT"
echo "CATALOG_PATH=$CATALOG_PATH"
echo "CATALOG_NAMES=$CATALOG_NAMES"
echo "STORAGE_CLASS=$STORAGE_CLASS"
echo "UNINSTALL=$UNINSTALL"
echo ""

if [[ "$UNINSTALL" -eq 1 ]]; then
     # delete configmap
    catalogNames=(${CATALOG_NAMES//[,]/ })
    for catalog in "${catalogNames[@]}"; do
        kubectl delete configmap ${catalog} --namespace ${NAMESPACE}
    done
    # delete service-broker
    kubectl delete service -l app=${APP} --namespace ${NAMESPACE}
    kubectl delete deployment -l app=${APP} --namespace ${NAMESPACE}
    # delete RBAC objects, if --rbac flag was used.
    kubectl delete serviceaccount -l app=${APP} --namespace ${NAMESPACE}
    kubectl delete clusterrolebindings -l app=${APP}

    echo
    echo "waiting for service-broker pod to stop running"
    for (( ; ; )); do
        pods=($(kubectl get pods --all-namespaces -l app=${APP} -o jsonpath='{range .items[*]}{.metadata.name} {end}'))
        total=${#pods[*]}
        if [[ ${total} -eq 0 ]] ; then
            break
        fi
        sleep 2
    done

    kubectl delete clusterservicebroker -l app=${APP}
    kubectl delete ns ${NAMESPACE}

    echo
    echo "Successfully uninstalled service-broker!"
    exit 0
fi

found=0
ns=($(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name} {end}'))
for n in "${ns[@]}"; do
    if [[ "$n" = "$NAMESPACE" ]]; then
        export found=1
    fi
done
if [[ "$found" -eq 0 ]]; then
    kubectl create ns ${NAMESPACE}
fi

catalogNames=(${CATALOG_NAMES//[,]/ })
for catalog in "${catalogNames[@]}"; do
    kubectl create configmap ${catalog} --namespace ${NAMESPACE} --from-file=hack/deploy/catalogs/${catalog}
done
${SCRIPT_LOCATION}hack/deploy/deployment.yaml | ${ONESSL} envsubst | kubectl apply -f -
${SCRIPT_LOCATION}hack/deploy/service.yaml | ${ONESSL} envsubst | kubectl apply -f -
${SCRIPT_LOCATION}hack/deploy/rbac.yaml | ${ONESSL} envsubst | kubectl apply -f -
${SCRIPT_LOCATION}hack/deploy/cluster_service_broker.yaml | ${ONESSL} envsubst | kubectl apply -f -

echo
echo "waiting until service-broker deployment is ready"
${ONESSL} wait-until-ready deployment ${NAME} --namespace ${NAMESPACE} || { echo "service-broker deployment failed to be ready"; exit 1; }

echo
echo "Successfully installed service-broker in $NAMESPACE namespace!"