---
description: >-
  This page outlines the PostgreSQL resources that are available in the Sandbox
  for developing codebundles.
---

# Postgres (Operator and test database)

The `postgres-database` namespace contains:&#x20;

* The [Zalando Postgres Operator ](https://github.com/zalando/postgres-operator)deployed via the [Helm Chart](https://postgres-operator.readthedocs.io/en/latest/quickstart/#helm-chart)
* A minimal 2 instance postresql instance

```
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: acid-minimal-cluster
spec:
  teamId: "acid"
  volume:
    size: 1Gi
  numberOfInstances: 2
  users:
    zalando:  # database owner
    - superuser
    - createdb
    foo_user: []  # role for application foo
  databases:
    foo: zalando  # dbname: owner
  preparedDatabases:
    bar: {}
  postgresql:
    version: "15"
```



The `runwhen-authors` service account has access to `get, list, watch` the resources in this namespace, along with:&#x20;

* Viewing secrets (in order to test database codebundles)
* Pod exec capabilities

#### Viewing Pods

```
# kubectl get pods -n postgres-database
NAME                                READY   STATUS    RESTARTS   AGE
acid-minimal-cluster-0              1/1     Running   0          13m
acid-minimal-cluster-1              1/1     Running   0          7m48s
postgres-operator-7d446d785-vhb98   1/1     Running   0          36m
```

#### Viewing Secrets&#x20;

```
# kubectl get secret -n postgres-database
NAME                                                                 TYPE                 DATA   AGE
foo-user.acid-minimal-cluster.credentials.postgresql.acid.zalan.do   Opaque               2      13m
postgres.acid-minimal-cluster.credentials.postgresql.acid.zalan.do   Opaque               2      13m
sh.helm.release.v1.postgres-operator.v1                              helm.sh/release.v1   1      36m
standby.acid-minimal-cluster.credentials.postgresql.acid.zalan.do    Opaque               2      13m
zalando.acid-minimal-cluster.credentials.postgresql.acid.zalan.do    Opaque               2      13m
```

#### Exec into the PostgreSQL Pod

```
# kubectl exec -it acid-minimal-cluster-0 -n postgres-database -- /bin/bash

 ____        _ _
/ ___| _ __ (_) | ___
\___ \| '_ \| | |/ _ \
 ___) | |_) | | | (_) |
|____/| .__/|_|_|\___/
      |_|

This container is managed by runit, when stopping/starting services use sv

Examples:

sv stop cron
sv restart patroni

Current status: (sv status /etc/service/*)

run: /etc/service/patroni: (pid 33) 920s
run: /etc/service/pgqd: (pid 34) 920s
root@acid-minimal-cluster-0:/home/postgres# 
```
