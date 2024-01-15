---
description: >-
  Access to the RunWhen Sandbox can help Authors to test codebundles against the
  same infrastructure that RunWhen uses for testing and demos.
---

# Sandbox Resources

## Sandbox Cluster

RunWhen operates a sandbox GKE cluster that is used for testing and demonstration purposes. For codebundle authors, RunWhen provides access to this cluster to ease the burden on setting up test infrastructure.&#x20;

## Application/Infrastructure Stacks

The Sandbox cluster provides many different application stacks, and also continually hosts a demo version of [Broken link](broken-reference "mention") - which provides some insight as to what is running in the cluster (see [here](https://runwhen-local.sandbox.runwhen.com/)).&#x20;

Some of the resources include:&#x20;

* ArgoCD
* Artifactory
* Cert-Manager
* Crossplane
* External-DNS
* FluxCD
* Ingress - Kong
* Ingress - Nginx
* Jenkins (Traditional)
* [jenkinsx.md](jenkinsx.md "mention")
* MongoDB (Operator and test database)
* Online Boutique
* Otel-Demo
* Postgres (Operator and test database)
* Vault (HashiCorp)

### Obtaining Sandbox Access

Access to the sandbox cluster is provided by a shared kubeconfig. Reach out via [Slack](https://runwhen.slack.com/join/shared\_invite/zt-1l7t3tdzl-IzB8gXDsWtHkT8C5nufm2A#/shared-invite/email) or [Discord](https://discord.com/invite/Ut7Ws4rm8Q) to connect with us for read-only access to the cluster.&#x20;

{% hint style="info" %}
A dedicated sandbox Vault instance is coming soon for sharing secrets / credentials with codebundle authors.&#x20;
{% endhint %}

### Requesting Additional Application Stacks

Want to write a new codebundle for an application stack that is missing from the Sandbox? Reach out via [Slack](https://runwhen.slack.com/join/shared\_invite/zt-1l7t3tdzl-IzB8gXDsWtHkT8C5nufm2A#/shared-invite/email) or [Discord](https://discord.com/invite/Ut7Ws4rm8Q) to connect with us and we can help. .&#x20;

