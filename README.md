# Deploy ManageIQ on OpenShift

[![Join the chat at https://gitter.im/ManageIQ/manageiq-pods](https://badges.gitter.im/ManageIQ/manageiq-pods.svg)](https://gitter.im/ManageIQ/manageiq-pods?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
**This guide will demo deploying ManageIQ in OpenShift as its example use-case but this method could actually be used in a different container cluster environment**

## Purpose

This example gives a base template to deploy a multi-pod ManageIQ appliance with the DB stored in a persistent volume on OpenShift. It provides a step-by-step setup including cluster administrative tasks as well as basic user information and commands. The ultimate goal of the project is to be able to decompose the ManageIQ appliance into several containers.

### Prerequisites:

* OpenShift Origin 1.5 or higher
* NFS or other compatible volume provider
* A cluster-admin user

### Cluster Sizing

In order to avoid random deployment failures due to resource starvation, we recommend a minimum cluster size for a **test** environment.

* 1 x Master node with at least 8 VCPUs and 12GB of RAM
* 2 x Nodes with at least 4 VCPUs and 8GB of RAM
* 20GB of storage for MIQ PV use

Other sizing considerations:

* Recommendations assume MIQ will be the only application running on this cluster.
* Alternatively, you can provision an infrastructure node to run registry/metrics/router/logging pods.

### Installing

`$ git clone https://github.com/ManageIQ/manageiq-pods.git`

### Pre-deployment preparation tasks

_**As basic user**_

Login to OpenShift and create a project

_**Note:**_ This section assumes you have a basic user.

`$ oc login -u <user> -p <password>`

   Next, create the project as follows:

```bash
$ oc new-project <project_name>
```

### Add the miq-anyuid and miq-orchestrator service accounts to the anyuid security context

_**Note:**_ The current MIQ images require the root user.

These service accounts for your namespace (project) must be added to the anyuid SCC before pods using the service accounts can run as root.

_**As admin**_

```bash
$ oc adm policy add-scc-to-user anyuid system:serviceaccount:<your-namespace>:miq-anyuid
$ oc adm policy add-scc-to-user anyuid system:serviceaccount:<your-namespace>:miq-orchestrator
```

Verify that the service accounts are now included in the anyuid scc
```
$ oc describe scc anyuid | grep Users
Users:					system:serviceaccount:<your-namespace>:miq-anyuid,system:serviceaccount:<your-namespace>:miq-orchestrator
```

### Set up the miq-httpd service account

#### If running without OCI systemd hooks (Minishift)

_**Note:**_ Minishift clusters are not equipped with OCI systemd hooks which are used to assist with containerized systemd deployments.

An extra SCC is used on Minishift to compensate for the lack of oci-systemd-hooks. **Please SKIP this step if your cluster is equipped with oci-systemd-hooks.**

__*As admin*__

Create the miq-sysadmin SCC:

```bash
$ oc create -f templates/miq-scc-sysadmin.yaml
```

The miq-httpd service account must be added to the miq-sysadmin SCC before the front-end httpd pod can run.

```bash
$ oc adm policy add-scc-to-user miq-sysadmin system:serviceaccount:<your-namespace>:miq-httpd
```

Verify that the miq-httpd service account is now included in the miq-sysadmin scc

```bash
$ oc describe scc miq-sysadmin | grep Users
Users:              system:serviceaccount:<your-namespace>:miq-httpd
```

#### If running with OCI systemd hooks

__*As admin*__

Add the miq-httpd service account to the anyuid SCC

```bash
$ oc adm policy add-scc-to-user anyuid system:serviceaccount:<your-namespace>:miq-httpd
```

Verify that the miq-httpd service account is now included in the anyuid scc

```bash
$ oc describe scc anyuid | grep Users
Users:              system:serviceaccount:<your-namespace>:miq-httpd
```

### Make a persistent volume to host the MIQ database data (if necessary)

A deployment will need a persistent volume (PV) to store data only if the database is running as a pod.

NFS PV templates are provided, **please skip this step you have
already configured persistent storage.**

For NFS backed volumes, please ensure your NFS server firewall is
configured to allow traffic on port 2049 (TCP) from the OpenShift
cluster.

_**Note:**_ Recommended permissions for the PV volumes are 777, root uid/gid owned.

_**As admin:**_

Creating the required PV may be a one or two step process. You may
create the initial *template* now, and then process them and create
the *PV* later, or you may do all of the processing and PV creation
in one pass

There are three parameters required to process the template. Only
`NFS_HOST` is required, `PV_SIZE` and `BASE_PATH` have sane defaults
already

* `PV_SIZE` - **Defaults** to the recommended PV size for the App/DB
  template (`5Gi`/`15Gi` respectively)
* `BASE_PATH` - **Defaults** to `/exports`
* `NFS_HOST` - **No Default** - Hostname or IP address of the NFS
  server

#### Method 1 - Create Template, Process and Create Later

This method first creates the template object in OpenShift and then
demonstrates how to process the template and fill in the required
parameters at a later time.

```
$ oc create -f templates/miq-pv-db-example.yaml
# ... do stuff ...
$ oc process manageiq-db-pv -p NFS_HOST=nfs.example.com | oc create -f -
```



#### Method 2 - Process Template and Create PV in one pass

```
# oc process templates/miq-pv-db-example.yaml -p NFS_HOST=nfs.example.com | oc create -f -
```

Verify PV creation

```bash
$ oc get pv
NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     STORAGECLASS   REASON    AGE
miq-db    15Gi       RWO           Retain          Available                                      1s
```

It is strongly suggested that you validate NFS share connectivity from an OpenShift node prior to attempting a deployment.

## Deploy MIQ

If you wish to add a SSL certificate now, you can edit the httpd template and provide that now.  Check the Edge Termination section of [Secured Routes](https://docs.okd.io/latest/architecture/networking/routes.html#secured-routes) for more information.
This can be easily changed later in the Openshift UI by navigating to *Your Project* -> Applications -> Routes -> httpd -> Actions -> Edit.

Application parameters can be specified in a parameters file. An example file can be found [in the project root](https://github.com/ManageIQ/manageiq-pods/blob/master/parameters)
The existing parameters file contains all the default values for template parameters. You can create a new file containing any customizations.

_**As basic user**_

```bash
$ ./bin/deploy <parameters_file>
```

## Deploy MIQ using an external database

Before you attempt an external DB deployment please ensure the following conditions are satisfied:

* Your OpenShift cluster can access the external PostgreSQL server
* The external PostgreSQL server must run version 10
* MIQ user, password and role have been created on the external PostgreSQL server
* The intended MIQ database is created and ownership has been assigned to the MIQ user

To use an external database, ensure that the `DATABASE_HOSTNAME` parameter is provided in your parameters file.
`DATABASE_NAME`, `DATABASE_PORT`, `DATABASE_USER`, and `DATABASE_PASSWORD` should also be checked and set if necessary.

## Verifying the setup was successful

_**Note:**_ The first deployment could take several minutes as OpenShift is downloading the necessary images.

### Confirm the deployed MIQ pods are bound to the correct SCC

Describe all pods and search for Security Policy

```bash
$ oc describe pods | grep -B2 "Security Policy"
Name:			httpd-1-1tmjp
Security Policy:	anyuid
--
Name:			manageiq-orchestrator-1-zs60q
Security Policy:	anyuid
--
Name:			memcached-1-qsjt0
Security Policy:	restricted
--
Name:			postgresql-1-0hhvv
Security Policy:	restricted
```

### Verify the persistent volume is attached to postgresql pod

```bash
$ oc volume pods --all
pods/postgresql-1-0hhvv
  pvc/manageiq-postgresql (allocated 100GiB) as miq-pgdb-volume
    mounted at /var/lib/pgsql/data
  unknown as miq-pg-configs
    mounted at /opt/app-root/src/postgresql-config/
  secret/default-token-mjmmb as default-token-mjmmb
    mounted at /var/run/secrets/kubernetes.io/serviceaccount
```

### Check readiness of the MIQ pods

_**Note:**_ Please allow ~5 minutes once pods are in Running state for MIQ to start responding on HTTPS

The READY column denotes the number of replicas and their readiness state

```bash
$ oc get pods
NAME                            READY     STATUS    RESTARTS   AGE
httpd-1-4qxzt                   1/1       Running   0          47s
manageiq-orchestrator-1-xxj8f   1/1       Running   0          48s
memcached-1-22blh               1/1       Running   0          47s
postgresql-1-n7rc4              1/1       Running   0          47s
```

Once the database has been migrated and the orchestrator pod is up and running, it will begin to start worker pods.
After a few minutes you can see the initial set of worker pods has been deployed and the user interface should be accessible.

```bash
$ oc get pods
NAME                            READY     STATUS    RESTARTS   AGE
event-handler-1-qgtkl           1/1       Running   0          3m
generic-1-3f0l5                 1/1       Running   0          3m
generic-1-6nc2d                 1/1       Running   0          3m
httpd-1-4qxzt                   1/1       Running   0          6m
manageiq-orchestrator-1-xxj8f   1/1       Running   0          6m
memcached-1-22blh               1/1       Running   0          6m
postgresql-1-n7rc4              1/1       Running   0          6m
priority-1-wklns                1/1       Running   0          3m
priority-1-x3xdn                1/1       Running   0          3m
reporting-1-6kbjc               1/1       Running   0          3m
reporting-1-h6g4c               1/1       Running   0          3m
schedule-1-clp5m                1/1       Running   0          3m
ui-1-h35wk                      1/1       Running   0          3m
web-service-1-f6nt0             1/1       Running   0          3m
websocket-1-mpws5               1/1       Running   0          3m
```

## Scale MIQ

ManageIQ worker deployments can be scaled from within the application web console.
Navigate to Configuration -> Server -> Workers tab to change the number of worker replicas.

Additional workers for provider operations will be deployed or removed by the orchestrator as providers are added or removed and as roles change.

_**Note:**_ The orchestrator will enforce its desired state over the worker replicas. This means that any changes made to desired replica numbers in the OpenShift UI will be quickly reverted by the orchestrator. 

## POD access and routes

### Get a shell on the MIQ pod

`$ oc rsh <pod_name> bash -l`

### Obtain host information from route
A route should have been deployed via template for HTTPS access on the MIQ pod

```bash
$oc get routes
NAME      HOST/PORT                              PATH      SERVICES   PORT      TERMINATION     WILDCARD
httpd     miq-dev.apps.example.com                         httpd      http      edge/Redirect   None
```
Examine output and point your web browser to the reported URL/HOST.

### Logging In

Per the ManageIQ project [basic configuration](http://manageiq.org/docs/get-started/basic-configuration) documentation, you can now login to the MIQ web interface using the default username (`admin`) and either the default password (`smartvm`) of the password configured using the `APPLICATION_ADMIN_PASSWORD` parameter.

## Backup and restore of the MIQ database

Backup and restore of the MIQ database can be achieved via openshift jobs. Keep in mind an extra PV will be required with enough capacity to store as many backup copies as needed.

A sample backup PV is supplied on templates, adjust the default settings to your site requirements before attempting to import.

### Create the backup PV

_** As admin user**_

`$ oc create -f templates/miq-pv-backup-example.yaml`

### Create the backup PVC

_**As basic user**_

`$ oc create -f templates/miq-backup-pvc.yaml`

### Verify the backup PVC was created correctly

The backup and restore job samples expect PVCs to be named "manageiq-backup" and "manageiq-postgresql" to setup volumes correctly.

```bash
$ oc get pvc
NAME                  STATUS    VOLUME    CAPACITY   ACCESSMODES   STORAGECLASS   AGE
manageiq-backup       Bound     pv0062    100Gi      RWO,ROX,RWX                  44s
manageiq-postgresql   Bound     pv0017    100Gi      RWO,ROX,RWX                  17m
```

### Backup API objects at the project level

```bash
$ oc get secret -o yaml --export=true > secrets.yaml
$ oc get pvc -o yaml --export=true > pvc.yaml
```

The MIQ secrets object contains important data regarding your deployment such as database encryption keys and other credentials, backup and save objects in a safe location.

### Launch a database backup

Backups can be initiated with the database online, the job will attempt to run immediately after creation.

`$ oc create -f templates/miq-backup-job.yaml`

The backup job will connect to the MIQ database pod and perform a full binary backup of the entire database cluster, it is based on pg_basebackup.

### Check the job status and logs

```bash
$ oc get pods
NAME                     READY     STATUS      RESTARTS   AGE
manageiq-backup-rrkw5    0/1       Completed   0          1h

$ oc logs manageiq-backup-rrkw5
== Starting MIQ DB backup ==
Current time is : Thu Jul 27 02:30:44 UTC 2017
transaction log start point: 0/2C000028 on timeline 1
86554/86554 kB (100%), 1/1 tablespace
transaction log end point: 0/2C01FBF8
pg_basebackup: base backup completed
Sucessfully finished backup : Thu Jul 27 02:30:57 UTC 2017
Backup stored at : /backups/miq_backup_20170727T023044
```

### Restoring a database backup

**The database restoration must be done OFFLINE**, scale down prior attempting this procedure otherwise corruption can occur.

```bash
$ oc scale dc/manageiq-orchestrator --replicas=0 # this should scale down all the worker pods as well
$ oc scale dc/httpd --replicas=0
$ oc scale dc/postgresql --replicas=0
```

Notes about restore procedure:

* The sample restore job will bind to the backup and production PG volumes via "manageiq-backup" and "manageiq-postgresql" PVCs by default
* If existing data is found on the production PG volume, the restore job will *NOT* delete this data, it will rename it and place it on the same volume
* The latest successful DB backup will be restored by default, this can be adjusted via the BACKUP_VERSION environment variable on restore object template

### Launch a database restore

`$ oc create -f miq-restore-job.yaml`

### Check the restore job status and logs

```bash
$ oc get pods
NAME                     READY     STATUS      RESTARTS   AGE
manageiq-backup-rrkw5    0/1       Completed   0          10h
manageiq-restore-7hgzc   0/1       Completed   0          8h
$ oc logs manageiq-restore-7hgzc
== Checking postgresql status ==
postgresql:5432 - no response
== Checking for existing PG data ==
Existing data found at : /restore/userdata
Existing data moved to : /restore/userdata_20170727T052008
== Starting MIQ DB restore ==
Current time is : Thu Jul 27 05:20:11 UTC 2017
tar: Read checkpoint 500
tar: Read checkpoint 1000
tar: Read checkpoint 1500
tar: Read checkpoint 2000
...
Sucessfully finished DB restore : Thu Jul 27 05:20:33 UTC 2017
```

### Re-scale postgresql DC and verify proper operation

`$ oc scale dc/postgresql --replicas=1`

Check the PG pod logs and readiness status, if successful, proceed to re-scale rest of deployment

```bash
$ oc scale dc/manageiq-orchestrator --replicas=1
$ oc scale dc/httpd --replicas=1
```

## Troubleshooting
Under normal circumstances the entire first time deployment process should take around ~10 minutes, indication of issues can be seen
by examination of the deployment events and pod logs.

### Re-trying a failed deployment

_**As basic user**_


```bash
$ oc get pods
NAME                              READY     STATUS    RESTARTS   AGE
manageiq-orchestrator-1-deploy    0/1       Error     0          25m
memcached-1-yasfq                 1/1       Running   0          24m
postgresql-1-wfv59                1/1       Running   0          24m

$ oc deploy manageiq-orchestrator --retry
Retried #1
Use 'oc logs -f dc/manageiq-orchestrator' to track its progress.
```
Allow a few seconds for the failed pod to get re-scheduled, then begin checking events and logs

```bash
$ oc describe pods <pod-name>
...
Events:
  FirstSeen	LastSeen	Count	From							SubobjectPath			Type		Reason		Message
  ---------	--------	-----	----							-------------			--------	------		-------
15m		15m		1	{kubelet ocp-eval-node-2.e2e.bos.redhat.com}	spec.containers{manageiq}	Warning		Unhealthy	Readiness probe failed: Get http://10.1.1.5:80/: dial tcp 10.1.1.5:80: getsockopt: connection refused
```

Liveness and Readiness probe failures indicate the pod is taking longer than expected to come alive/online, check pod logs.

## Building Images on OpenShift
It is possible to build the images used for this project in OpenShift.

A template is provided which creates build configs and image streams for all of the required images.
By default the buildconfigs are set up to pull the master branch of both this repository and the ManageIQ main repository.

To deploy builds into the project `test` for a feature branch called `my_feature` which exists in your fork of manageiq and manageiq-pods you would deploy the template like this:

```bash
$ oc process -f templates/helpers/build-template.yaml -p IMAGE_NAMESPACE=test -p SOURCE_REPOSITORY_URL=https://github.com/<your_fork_name>/manageiq-pods -p SOURCE_REPOSITORY_REF=my_feature -p MIQ_ORG=<your_fork_name> -p MIQ_REF=my_feature
```

You would then want to set the ORCHESTRATOR_IMAGE_NAMESPACE parameter to something like `docker-registry.default.svc:5000/test` when deploying the application. This will ensure that the newly built images are deployed.

## Configuring External Authentication
Configuring the httpd pod for external authentication is done by updating the `httpd-auth-configs` configuration map to include all necessary config files and certificates. Upon startup, the httpd pod overlays its files with the ones specified in the `auth-configuration.conf` file in the configuration map. This is done by the `initialize-httpd-auth` service that runs before httpd.

The config map includes the following:

* The authentication type `auth-type`, default is `internal`

	This parameter drives which configuration files httpd will load upon start-up. Supported values are:

	| Value    | External-Authentication Configuration |
	| ---------|---------------------------------------|
	| internal | Application Based Authentication (_default_) - Database, Ldap/Ldaps, Amazon |
	| external | IPA, IPA 2-factor authentication, IPA/AD Trust, Ldap (OpenLdap, RHDS, Active Directory, etc.)
	| active-directory | Active Directory domain realm join
	| saml | SAML based authentication (Keycloak, ADFS, etc.)
	| oidc | OpenID-Connect based authentication (Keycloak, ADFS, etc.)

* The kerberos realms to join `auth-kerberos-realms`, default is `undefined`

	When configuring external authentication against IPA, Active Directory or Ldap, this parameter defines the kerberos realm httpd is configured against, i.e. `example.com`

	When specifying multiple Kerberos realms, they need to be space separated.

* The external authentication configuration file `auth-configuration.conf` which declares the list of files to overlay upon startup if `auth-type` is other than `internal`.

	Syntax for the file is as follows:

	```
	# for comments
	file = basename1 target_path1 permission1
	file = basename2 target_path2 permission2
	```



For the files to overlay on the httpd pod, one `file` directive is needed per file.

* the `basename` is the name of the source file in the configuration map.
* `target_path` is the path of the file on the pod to overwrite, i.e. `/etc/sssd/sssd.conf`
* `permission` is optional, by default files are copied using the pod's default umask, owner and group, so files are created as mode 644 owner root, group root.

optional `permission` can be specified as follows:

* mode
* mode:owner
* mode:owner:group

Reflecting the mode and ownership to set the copied files to.

_Examples_:

* 755
* 640:root
* 644:root:apache

Binary files can be specified in the configuration map in their base64 encoded format with a basename having a `.base64` extension. Such files are then converted back to binary as they are copied to their target path.

When an /etc/sssd/sssd.conf file is included in the configuration map, the httpd pod automatically enables the sssd service upon startup.

### Sample external authentication configuration for SAML:

Excluding the content of the files, a SAML auth-config map data section may look like:

```bash
apiVersion: v1
data:
  auth-type: saml
  auth-kerberos-realms: example.com
  auth-configuration.conf: |
    #
    # Configuration for SAML authentication
    #
    file = manageiq-remote-user.conf        /etc/httpd/conf.d/manageiq-remote-user.conf        644
    file = manageiq-external-auth-saml.conf /etc/httpd/conf.d/manageiq-external-auth-saml.conf 644
    file = idp-metadata.xml                 /etc/httpd/saml2/idp-metadata.xml                  644
    file = sp-key.key                       /etc/httpd/saml2/sp-key.key                        600:root:root
    file = sp-cert.cert                     /etc/httpd/saml2/sp-cert.cert                      644
    file = sp-metadata.xml                  /etc/httpd/saml2/sp-metadata.xml                   644
  manageiq-remote-user.conf: |
    RequestHeader unset X_REMOTE_USER
    ...
  manageiq-external-auth-saml.conf: |
    LoadModule auth_mellon_module modules/mod_auth_mellon.so
    ...
  idp-metadata.xml: |
    <EntitiesDescriptor ...
      ...
    </EntitiesDescriptor>
  sp-key.key: |
    -----BEGIN PRIVATE KEY-----
       ...
    -----END PRIVATE KEY-----
  sp-cert.cert: |
    -----BEGIN CERTIFICATE-----
       ...
    -----END CERTIFICATE-----
  sp-metadata.xml: |
    <EntityDescriptor ...
       ...
    </EntityDescriptor>
```

The authentication configuration map can be defined and customized in the httpd pod as follows:

```bash
$ oc edit configmaps httpd-auth-configs
```

Or simply replaced if generated and edited externally as follows:

```bash
$ oc replace configmaps httpd-auth-configs --filename external-auth-configmap.yaml
```

Then redeploy the httpd pod for the new authentication configuration to take effect.

Support for automatically generating authentication configuration maps for the httpd pod is provided by [ManageIQ/httpd\_configmap\_generator](https://github.com/ManageIQ/httpd_configmap_generator). Please see the [README.md](https://github.com/ManageIQ/httpd_configmap_generator/blob/master/README.md) in that repo for further details.
