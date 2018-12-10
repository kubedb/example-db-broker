# Walkthrough Postgres

To keep things isolated, this tutorial uses a separate namespace called `service-broker` throughout this tutorial.

```console
$ kubectl create ns service-broker
namespace/service-broker created

If we've AppsCode Service Broker installed, then we are ready for going forward. If not, then the [installation instructions](/docs/setup/install.md) are ready.

This document assumes that you've installed Service Catalog onto your cluster. If you haven't, please see the [installation instructions](https://github.com/kubernetes-incubator/service-catalog/blob/v0.1.27/docs/install.md). Optionally you may install the Service Catalog CLI, svcat. Examples for both svcat and kubectl are provided so that you may follow this walkthrough using svcat or using only kubectl.

> All commands in this document assume that you're operating out of the root of this repository.

## Check ClusterServiceClass and ClusterServicePlan for Postgres

First, list the available `ClusterServiceClass` resources:

```console
$ kubectl get clusterserviceclasses -o=custom-columns=NAME:.metadata.name,EXTERNAL\ NAME:.spec.externalName
NAME            EXTERNAL NAME
elasticsearch   elasticsearch
memcached       memcached
mongodb         mongodb
mysql           mysql
postgresql      postgresql
redis           redis

$ svcat get classes
      NAME        NAMESPACE                     DESCRIPTION
+---------------+-----------+-------------------------------------------------+
  elasticsearch               The example service from the ElasticSearch
                              database!
  memcached                   The example service from the Memcache database!
  mongodb                     The example service from the MongoDB database!
  mysql                       The example service from the MySQL database!
  postgresql                  The example service from the PostgreSQL
                              database!
  redis                       The example service from the Redis database!
```

> **NOTE:** The above kubectl command uses a custom set of columns. The **`NAME`** field is the Kubernetes name of the `ClusterServiceClass` and the **`EXTERNAL NAME`** field is the human-readable name for the service that the broker returns.

Now, describe the `postgresql` class from the `Service Broker`.

```console
$ svcat describe class postgresql
  Name:              postgresql
  Scope:             cluster
  Description:       The example service from the PostgreSQL database!
  Kubernetes Name:   postgresql
  Status:            Active
  Tags:
  Broker:            service-broker

Plans:
      NAME                 DESCRIPTION
+---------------+--------------------------------+
  ha-postgresql   This plan is for getting HA
                  postgres database under the
                  `postgresql` service
  default         This plan is for getting
                  standalone postgres database
                  under the `postgresql` service
```

To view the details of the `default` plan of `postgresql` class:

```console
$ kubectl get clusterserviceplans -o=custom-columns=NAME:.metadata.name,EXTERNAL\ NAME:.spec.externalName
NAME                        EXTERNAL NAME
elasticsearch-6-3           default
elasticsearch-cluster-6-3   elasticsearch-cluster
ha-postgresql-10-2          ha-postgresql
memcached-1-5-4             default
mongodb-3-6                 default
mongodb-cluster-3-6         mongodb-cluster
mysql-8-0                   default
postgresql-10-2             default
redis-4-0                   default

$ svcat get plan postgresql/default --scope cluster
   NAME     NAMESPACE     CLASS                    DESCRIPTION
+---------+-----------+------------+------------------------------------------+
  default               postgresql   This plan is for getting standalone
                                     postgres database under the `postgresql`
                                     service

$ svcat describe plan postgresql/default --scope cluster
  Name:              default
  Description:       This plan is for getting standalone postgres database under the `postgresql` service
  Kubernetes Name:   postgresql-10-2
  Status:            Active
  Free:              true
  Class:             postgresql

Instances:
No instances defined
```

> Here we,ve used `--scope` flag to specify that our `ClusterServiceBroker`, `ClusterServiceClass` and `ClusterServiceBroker` resources are cluster scoped (not namespaced scope)

## Provisioning: Creating a New ServiceInstance

Since a `ClusterServiceClass` named `postgresql` exists in the cluster with a `ClusterServicePlan` named `default`, we can create a `ServiceInstance` ponting to them.

> Unlike `ClusterServiceBroker`, `ClusterServiceClass` and `ClusterServicePlan` resources, `ServiceInstance` resources must be namespaced. The latest version of service catelog supports `ServiceBroker`, `ServiceClass` and `ServicePlan` resources that are namespace scoped and alternative to `ClusterServiceBroker`, `ClusterServiceClass` and `ClusterServicePlan` resources.

Create the `ServiceInstance`:

```console
$ kubectl create -f docs/examples/postgresql-instance.yaml
serviceinstance.servicecatalog.k8s.io/my-broker-postgresql-instance created
```

After it is created, the service catalog controller will communicate with the service broker server to initaiate provisioning. Now, see the details:

```console
$ svcat describe instance my-broker-postgresql-instance --namespace service-broker
  Name:        my-broker-postgresql-instance
  Namespace:   service-broker
  Status:      Ready - The instance was provisioned successfully @ 2018-12-03 09:27:04 +0000 UTC
  Class:       postgresql
  Plan:        default

Parameters:
  No parameters defined

Bindings:
No bindings defined
```

The yaml configuration of this `ServiceInstance`:

```console
kubectl get serviceinstance my-broker-postgresql-instance --namespace service-broker -o yaml
```

Output:

```yaml
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceInstance
metadata:
  creationTimestamp: 2018-12-03T09:27:03Z
  finalizers:
  - kubernetes-incubator/service-catalog
  generation: 1
  labels:
    app: service-broker
  name: my-broker-postgresql-instance
  namespace: service-broker
  resourceVersion: "1074"
  selfLink: /apis/servicecatalog.k8s.io/v1beta1/namespaces/service-broker/serviceinstances/my-broker-postgresql-instance
  uid: 980c74b7-f6dd-11e8-89f4-0242ac110003
spec:
  clusterServiceClassExternalName: postgresql
  clusterServiceClassRef:
    name: postgresql
  clusterServicePlanExternalName: default
  clusterServicePlanRef:
    name: postgresql-10-2
  externalID: 980c747f-f6dd-11e8-89f4-0242ac110003
  updateRequests: 0
  userInfo:
    groups:
    - system:masters
    - system:authenticated
    uid: ""
    username: minikube-user
status:
  asyncOpInProgress: false
  conditions:
  - lastTransitionTime: 2018-12-03T09:27:04Z
    message: The instance was provisioned successfully
    reason: ProvisionedSuccessfully
    status: "True"
    type: Ready
  deprovisionStatus: Required
  externalProperties:
    clusterServicePlanExternalID: postgresql-10-2
    clusterServicePlanExternalName: default
    userInfo:
      groups:
      - system:masters
      - system:authenticated
      uid: ""
      username: minikube-user
  observedGeneration: 1
  orphanMitigationInProgress: false
  provisionStatus: Provisioned
  reconciledGeneration: 1
```

## Binding: Creating a ServiceBinding for this ServiceInstance

We've now a `ServiceInstance` ready. To use this we've to bind it. So, create a `ServiceBinding` resource:

```console
$ kubectl create -f docs/examples/postgresql-binding.yaml
servicebinding.servicecatalog.k8s.io "my-broker-postgresql-binding" created
```

Once the `ServiceBinding` resource is created, the service catalog controller initiate binding process by communicating with the service broker server. In general, this step makes the broker server to provide the necessary credentials. Then the service catalog controller will insert them into a Kubernetes `Secret` object.

```console
$ kubectl get servicebindings my-broker-postgresql-binding --namespace service-broker -o=custom-columns=NAME:.metadata.name,INSTANCE\ REF:.spec.instanceRef.name,SECRET\ NAME:.spec.secretName
NAME                           INSTANCE REF                    SECRET NAME
my-broker-postgresql-binding   my-broker-postgresql-instance   my-broker-postgresql-secret

$ svcat get bindings --namespace service-broker
              NAME                 NAMESPACE                INSTANCE              STATUS
+------------------------------+----------------+-------------------------------+--------+
  my-broker-postgresql-binding   service-broker   my-broker-postgresql-instance   Ready

$ svcat describe bindings my-broker-postgresql-binding --namespace service-broker
  Name:        my-broker-postgresql-binding
  Namespace:   service-broker
  Status:      Ready - Injected bind result @ 2018-12-03 09:41:04 +0000 UTC
  Secret:      my-broker-postgresql-secret
  Instance:    my-broker-postgresql-instance

Parameters:
  No parameters defined

Secret Data:
  Protocol   10 bytes
  database   8 bytes
  host       55 bytes
  password   16 bytes
  port       4 bytes
  uri        108 bytes
  username   8 bytes
```

You can see the secret data by passing `--show-secrets` flag to the above command. The yaml configuration of this `ServiceBinding` resource is as follows:

```console
kubectl get servicebindings my-broker-postgresql-binding --namespace service-broker -o yaml
```

Output:

```yaml
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceBinding
metadata:
  creationTimestamp: 2018-12-03T09:41:04Z
  finalizers:
  - kubernetes-incubator/service-catalog
  generation: 1
  labels:
    app: service-broker
  name: my-broker-postgresql-binding
  namespace: service-broker
  resourceVersion: "1080"
  selfLink: /apis/servicecatalog.k8s.io/v1beta1/namespaces/service-broker/servicebindings/my-broker-postgresql-binding
  uid: 8d4b82b3-f6df-11e8-89f4-0242ac110003
spec:
  externalID: 8d4b823a-f6df-11e8-89f4-0242ac110003
  instanceRef:
    name: my-broker-postgresql-instance
  secretName: my-broker-postgresql-secret
  userInfo:
    groups:
    - system:masters
    - system:authenticated
    uid: ""
    username: minikube-user
status:
  asyncOpInProgress: false
  conditions:
  - lastTransitionTime: 2018-12-03T09:41:04Z
    message: Injected bind result
    reason: InjectedBindResult
    status: "True"
    type: Ready
  externalProperties:
    userInfo:
      groups:
      - system:masters
      - system:authenticated
      uid: ""
      username: minikube-user
  orphanMitigationInProgress: false
  reconciledGeneration: 1
  unbindStatus: Required
```

Here, the status has `Ready` condition which means the binding is now ready for use. This binding operation create a `Secret` named `my-broker-postgresql-secret` in namespace `service-broker`.

```console
$ kubectl get secrets --namespace service-broker
NAME                                 TYPE                                  DATA   AGE
default-token-ghn5f                  kubernetes.io/service-account-token   3      22m
my-broker-postgresql-secret          Opaque                                7      2m6s
postgresql-10-2-7fmfsb-auth          Opaque                                2      16m
postgresql-10-2-7fmfsb-token-ngrjt   kubernetes.io/service-account-token   3      16m
service-broker-token-wgp82           kubernetes.io/service-account-token   3      22m
```

## Unbinding: Deleting the ServiceBinding

We can now delete the `ServiceBinding` resource we created in the `Binding` step (it is called `Unbinding` the `ServiceInstance`)

```console
$ kubectl delete servicebinding my-broker-postgresql-binding --namespace service-broker
servicebinding.servicecatalog.k8s.io "my-broker-postgresql-binding" deleted

$ svcat unbind my-broker-postgresql-instance --namespace service-broker
deleted my-broker-postgresql-binding
```

After completion of unbinding, the `Secret` named `my-broker-postgresql-secret` should be deleted.

```console
$ kubectl get secrets --namespace service-broker
NAME                                 TYPE                                  DATA   AGE
default-token-ghn5f                  kubernetes.io/service-account-token   3      23m
postgresql-10-2-7fmfsb-auth          Opaque                                2      17m
postgresql-10-2-7fmfsb-token-ngrjt   kubernetes.io/service-account-token   3      17m
service-broker-token-wgp82           kubernetes.io/service-account-token   3      23m
```

## Deprovisioning: Deleting the ServiceInstance

After unbinding the `ServiceInstance`, our next step is deleting the `ServiceInstance` resource we created before at the step of provisioning. It is called `Deprovisioning`.

```console
$ kubectl delete serviceinstance my-broker-postgresql-instance --namespace service-broker
serviceinstance.servicecatalog.k8s.io "my-broker-postgresql-instance" deleted

$ svcat deprovision my-broker-postgresql-instance --namespace service-broker
deleted my-broker-postgresql-instance
```

## Cleanup

Now, we've to clean the cluster. For this, just [uninstall](/docs/setup/uninstall.md) the broker. It'll delete the `ClusterServiceBroker` resource. Then service catalog controller automatically delete all `ClusterServiceClass` and `ClusterServicePlan` resources that came from that broker.

```console
$ kubectl get clusterserviceclasses
No resources found.

$ svcat get classes
  NAME   NAMESPACE   DESCRIPTION
+------+-----------+-------------+
```