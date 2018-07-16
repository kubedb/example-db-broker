package db_broker

import (
	jsonTypes "github.com/appscode/go/encoding/json/types"
	"github.com/appscode/go/types"
	"github.com/appscode/kutil"
	"github.com/golang/glog"
	api "github.com/kubedb/apimachinery/apis/kubedb/v1alpha1"
	cs "github.com/kubedb/apimachinery/client/clientset/versioned/typed/kubedb/v1alpha1"
	"github.com/kubedb/apimachinery/client/clientset/versioned/typed/kubedb/v1alpha1/util"
	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/tools/clientcmd"
)

type MySQLProvider struct {
	extClient cs.KubedbV1alpha1Interface
	//mysqls map[string]*api.MySQL
}

func NewMySQLProvider(kubeConfig string) Provider {
	config, err := clientcmd.BuildConfigFromFlags("", kubeConfig)
	if err != nil {
		panic(err)
	}
	return &MySQLProvider{
		extClient: cs.NewForConfigOrDie(config),
		//mysqls: make(map[string]*api.MySQL),
	}
}

func MySQL(name, namespace string) *api.MySQL {
	return &api.MySQL{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
		},
		Spec: api.MySQLSpec{
			Version: jsonTypes.StrYo("5.7"),
			Storage: corev1.PersistentVolumeClaimSpec{
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceStorage: resource.MustParse("1Gi"),
					},
				},
				StorageClassName: types.StringP("standard"),
			},
		},
	}
}

func (p MySQLProvider) Create(name, namespace string) error {
	glog.Infof("Create(%q, %q) error {}", name, namespace)
	myObj := MySQL(name, namespace)
	//p.mysqls[name] = myObj

	_, err := p.extClient.MySQLs(myObj.Namespace).Create(myObj)
	if err != nil {
		return err
	}
	err = wait.PollImmediate(kutil.RetryInterval, kutil.ReadinessTimeout, func() (bool, error) {
		mysqldb, err := p.extClient.MySQLs(myObj.Namespace).Get(myObj.Name, metav1.GetOptions{})
		if err != nil {
			return false, nil
		}
		return mysqldb.Status.Phase == api.DatabasePhaseRunning, nil
	})

	glog.Infof("Create(%q, %q) error {} complete", name, namespace)
	return err
}

func (p MySQLProvider) Delete(name, namespace string) error {
	glog.Infof("Delete(%q %q) error {}", name, namespace)
	//meta := p.mysqls[name].ObjectMeta
	if err := p.extClient.MySQLs(namespace).Delete(name, &metav1.DeleteOptions{}); err != nil {
		return err
	}

	err := wait.PollImmediate(kutil.RetryInterval, kutil.ReadinessTimeout, func() (bool, error) {
		dormantDatabase, err := p.extClient.DormantDatabases(namespace).Get(namespace, metav1.GetOptions{})
		if err != nil {
			return false, nil
		}
		dormantDatabase, _, err = util.PatchDormantDatabase(p.extClient, dormantDatabase, func(in *api.DormantDatabase) *api.DormantDatabase {
			in.Spec.WipeOut = true
			return in
		})
		return true, nil
	})
	if err != nil {
		return err
	}

	glog.Infof("Delete(%q %q) error {} complete", name, namespace)
	return p.extClient.DormantDatabases(namespace).Delete(name, deleteInBackground())
	//if p.extClient.DormantDatabases(meta.Namespace).Delete(meta.Name, deleteInBackground()); err != nil {
	//	return err
	//}
	//err = wait.PollImmediate(kutil.RetryInterval, kutil.ReadinessTimeout, func() (bool, error) {
	//	dormantDatabase, err := p.extClient.DormantDatabases(meta.Namespace).Get(meta.Name, metav1.GetOptions{})
	//	if err != nil {
	//		return false, nil
	//	}
	//	if err != nil {
	//		return false, nil
	//	}
	//	return len(podList.Items) == 0, nil
	//})
}

func (p MySQLProvider) Bind(
	service corev1.Service,
	params map[string]interface{},
	data map[string]interface{}) (*Credentials, error) {

	if len(service.Spec.Ports) == 0 {
		return nil, errors.Errorf("no ports found")
	}
	svcPort := service.Spec.Ports[0]

	host := buildHostFromService(service)

	database := ""
	if dbVal, ok := params["mysqlDatabase"]; ok {
		database = dbVal.(string)
	}

	var user, password string
	userVal, ok := params["mysqlUser"]
	if ok {
		user = userVal.(string)

		passwordVal, ok := data["mysqlPassword"]
		if !ok {
			return nil, errors.Errorf("mysql-password not found in secret keys")
		}
		password = passwordVal.(string)
	} else {
		user = "root"

		rootPassword, ok := data["password"]
		if !ok {
			return nil, errors.Errorf("mysql-root-password not found in secret keys")
		}
		password = rootPassword.(string)
	}

	creds := Credentials{
		Protocol: svcPort.Name,
		Port:     svcPort.Port,
		Host:     host,
		Username: user,
		Password: password,
		Database: database,
	}
	creds.URI = buildURI(creds)

	return &creds, nil
}
