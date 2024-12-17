# Kubernetes Generation Rule Examples

The examples below will illustrate different configurations of Generation Rules and Templates. In general, every Generation Rule should render one or more templates, which directly correspond to objects that are optional in the RunWhen platform. Every Generation Rule **must** create an SLX (which is the parent object), and will render _**one or more**_ SLI, SLO, Runbook, or Workflow&#x20;

## Simple Example - Match Every Namespace

### Generation Rule

In this example, the generation rule is configured match and render the appropriate templates for _**every namespace found in every cluster**_.&#x20;

```
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  platform: kubernetes                                   # Kubernetes is the default when platform is not specified
  generationRules:                                       
    - resourceTypes:                        
        - namespace                                      # Match Kubernetes Namespaces
      matchRules:
        - type: pattern
          pattern: ".+"                                  # Match any pattern
          properties: [name]                             # Use the name for matching
          mode: substring
      slxs:
        - baseName: ns-health                            # Use this when generating SLX names
          levelOfDetail: basic                           # Even when doing basic scans, include this resource
          qualifiers: ["namespace", "cluster"]           # Generate 1 SLX for every namespace found in every cluster
          baseTemplateName: k8s-namespace-healthcheck    # Use this prefix looking for files in the templates folder
          outputItems:
            - type: slx
            - type: sli
            - type: slo
            - type: runbook
              templateName: k8s-namespace-healthcheck-taskset.yaml
            - type: workflow
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-namespace-healthcheck/.runwhen/generation-rules/k8s-namespace-healthcheck.yaml)

### SLX Template

So, in the above example, we will generate an SLX for every namespace found in every cluster, and for each SLX, we will render the slx, sli, slo, runbook, and workflow templates found in the `templates` directory. The complete `.runwhen`directory is as follows:&#x20;

```
k8s-namespace-healthcheck# tree .runwhen 
.runwhen
├── generation-rules
│   └── k8s-namespace-healthcheck.yaml
└── templates
    ├── k8s-namespace-healthcheck-sli.yaml
    ├── k8s-namespace-healthcheck-slo.yaml
    ├── k8s-namespace-healthcheck-slx.yaml
    ├── k8s-namespace-healthcheck-taskset.yaml
    └── k8s-namespace-healthcheck-workflow.yaml
```

Each file in the template directory is a jinja template that supports substitution from the resource that was discovered. For example, the SLX template is as follows:&#x20;

```
apiVersion: runwhen.com/v1
kind: ServiceLevelX
metadata:
  name: {{slx_name}}                                      
  ### ^Always add this - it is auto generated. 
  
  labels:
    {% raw %}
{% include "common-labels.yaml" %}                    
    ### ^Always add this
    
  annotations:    
    {% include "common-annotations.yaml" %}
{% endraw %}               
    ### ^Always add this
    
spec:
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/kubernetes/resources/labeled/ns.svg
  alias: {{namespace.name}} Namespace Health              
  ### ^A useful name that helps identify the resource. 
  
  asMeasuredBy: Aggregate score based on Kubernetes API Server queries
  ### ^Paired with the statement, describes how the statement should be measured.
   
  configProvided:
  - name: OBJECT_NAME
    value: {{match_resource.resource.metadata.name}}
    ### ^This is sometimes extra metadata to attach to an object. 
    
  owners:
  - {{workspace.owner_email}}
    ### ^Always add this. This is the contact for escalations on the specific SLX.
     
  statement: Overall health for {{namespace.name}} should be 1, 99% of the time. # A helpful statement for someone viewing the SLX to understand more about it's desired health or automation scripts. 
  ### ^Paired with the asMeasureBy, this often describes the obejective of the SLX. 
  
  additionalContext:
  ### ^Additional context can be used for debuggging or Engineering Assistant search enrichment. 
    namespace: "{{match_resource.resource.metadata.name}}"
    labelMap: "{{match_resource.resource.metadata.labels}}"
    cluster: "{{ cluster.name }}"
    context: "{{ cluster.context }}"
    subscription_id: "{{ cluster.subscription_id }}"
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-namespace-healthcheck/.runwhen/templates/k8s-namespace-healthcheck-slx.yaml)

A fully rendered example of the above template is as follows:&#x20;

```
apiVersion: runwhen.com/v1
kind: ServiceLevelX
metadata:
  name: b-sandbox--ob-grnsucsc1c-ns-health-0230f7f7
  labels:
    slx: b-sandbox--ob-grnsucsc1c-ns-health-0230f7f7
    workspace: b-sandbox
  annotations:
    fullSlxName: online-boutique-gke-runwhen-nonprod-sandbox-us-central1-sandbox-cluster-1-cluster-ns-health-0230f7f7
    sourceGenerationRuleRepoURL: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    sourceGenerationRuleRepoRef: main
    sourceGenerationRulePath: codebundles/k8s-namespace-healthcheck/.runwhen/generation-rules/k8s-namespace-healthcheck.yaml
    config.runwhen.com/last-updated-by: workspace-builder
    qualifiers: '{''namespace'': ''online-boutique'', ''cluster'': ''gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster''}'
spec:
  imageURL: https://storage.googleapis.com/runwhen-nonprod-shared-images/icons/kubernetes/resources/labeled/ns.svg
  alias: online-boutique Namespace Health
  asMeasuredBy: Aggregate score based on Kubernetes API Server queries
  configProvided:
  - name: OBJECT_NAME
    value: online-boutique
  owners:
  - jarod@runwhen.com
  statement: Overall health for online-boutique should be 1, 99% of the time.
  additionalContext:
    namespace: online-boutique
    labelMap: '{''kubernetes.io/metadata.name'': ''online-boutique'', ''kustomize.toolkit.fluxcd.io/name'':
      ''flux-system'', ''kustomize.toolkit.fluxcd.io/namespace'': ''flux-system''}'
    cluster: gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster
    context: gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster
    subscription_id: missing_workspaceInfo_custom_variable

```



## Complex Example - Match HTTPs Ingress

### Generation Rule

In this example, the generation rule is configured match and render the appropriate templates for _**every Kubernetes Ingress object with TLS enabled**_. &#x20;

```
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
platform: kubernetes                                     # Kubernetes is the default when platform is not specified
  generationRules:
    - resourceTypes:
        - ingress                                        # Match Ingress objects
      matchRules:
        - type: and                                      # Match when both conditions below are met
          matches:
            - type: pattern
              pattern: ".+"
              properties: [name]                          # Match on any name
              mode: substring
            - type: pattern
              pattern: ".+"
              properties: [spec/tls/hosts]                # Match on this field with any content 
              mode: substring
      slxs:
        - baseName: http-ok-tls-test
          qualifiers: ["resource", "namespace", "cluster"] # Generate 1 SLX for every ingress object found in every namespace in every cluster.
          baseTemplateName: http-ok-tls
          levelOfDetail: basic                             # Even when doing basic scans, include this resource
          outputItems:
            - type: slx
            - type: sli
            - type: slo
            - type: runbook
              templateName: http-ok-tls-taskset.yaml
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/curl-http-ok/.runwhen/generation-rules/http-ok-tls.yaml)

### SLI Template

In the previous example, we outlined an SLX template that was generated for every namespace found in every cluster.  In this example, we will highlight the SLI template that is found in the `templates` directory. The \*complete `.runwhen`directory is as follows:&#x20;

```
.runwhen
├── generation-rules
│   ├── http-ok-tls.yaml
└── templates
    ├── http-ok-tls-sli.yaml
    ├── http-ok-tls-slo.yaml
    ├── http-ok-tls-slx.yaml
    └── http-ok-tls-taskset.yaml

```

{% hint style="info" %}
\*Note: The [curl-http-ok CodeBundle](https://github.com/runwhen-contrib/rw-cli-codecollection/tree/main/codebundles/curl-http-ok)[ ](https://registry.runwhen.com/CodeCollection/rw-cli-codecollection/curl-http-ok/health/)is a good example of having multiple generation rules and templates that leverage the same CodeBundle, but with differing configuration templates. View all generation rules for this CodeBundle at [this link](https://github.com/runwhen-contrib/rw-cli-codecollection/tree/main/codebundles/curl-http-ok/.runwhen/generation-rules).&#x20;
{% endhint %}

Since the previous example shows an SLX, this example will outline the SLI template:&#x20;

```
apiVersion: runwhen.com/v1
kind: ServiceLevelIndicator
metadata:
  name: {{slx_name}}                                      
  ### ^Always add this - it is auto generated. 
  
  labels:
    {% raw %}
{% include "common-labels.yaml" %}                    
    ### ^Always add this
    
  annotations:    
    {% include "common-annotations.yaml" %}               
    ### ^Always add this
    
spec:
  displayUnitsLong: OK
  ### ^How the chart units should be displayed (long form)
  
  displayUnitsShort: ok
  ### ^How the chart units should be displayed (short form)

  locations:
    - {{default_location}}
    ### ^Always add this
    
  description: Measures the response code and latency to the ingress object. 
  ### ^Describe what the SLI measures. 
  
  codeBundle:
    {% if repo_url %}
    repoUrl: {{repo_url}}
    {% else %}
    repoUrl: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    ### ^The default url to the CodeCollection. 
    
    {% endif %}
    {% if ref %}
    ref: {{ref}}
    {% else %}
    ref: main
    {% endif %}
{% endraw %}
    pathToRobot: codebundles/curl-http-ok/sli.robot
    ### ^The default path to the CodeBundle code
    
    ### ^The jijna if/else above is used to support user overrides for forks/branches/etc.
 
  intervalStrategy: intermezzo
  intervalSeconds: 30
  ### ^How often to run the SLI code. 
  
  configProvided:
    - name: URL
      value: https://{{match_resource.resource.spec.tls[0].hosts[0]}}
      ### ^The rendered value from the discovered/matched resource. 
       
    - name: TARGET_LATENCY
      value: '1.2'
      ### ^A sensible default for the code to function. 
      
    - name: DESIRED_RESPONSE_CODE
      value: '200'
      ### ^A sensible default for the code to function. 
      
  secretsProvided: []
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/curl-http-ok/.runwhen/templates/http-ok-tls-sli.yaml)

A fully rendered example of the above template is as follows:&#x20;

```
apiVersion: runwhen.com/v1
kind: ServiceLevelIndicator
metadata:
  name: b-sandbox--sas-tt-grnsucsc1c-http-ok-tls-aks-c4cf8a15
  labels:
    slx: b-sandbox--sas-tt-grnsucsc1c-http-ok-tls-aks-c4cf8a15
    workspace: b-sandbox
  annotations:
    fullSlxName: sample-app-service-trouble-town-gke-runwhen-nonprod-sandbox-us-central1-sandbox-cluster-1-cluster-http-ok-tls-aks-c4cf8a15
    sourceGenerationRuleRepoURL: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    sourceGenerationRuleRepoRef: main
    sourceGenerationRulePath: codebundles/curl-http-ok/.runwhen/generation-rules/http-ok-tls-aks-public-loadbalancer-ext-dns-tls.yaml
    config.runwhen.com/last-updated-by: workspace-builder
    qualifiers: '{''resource'': ''sample-app-service'', ''namespace'': ''trouble-town'',
      ''cluster'': ''gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster''}'
spec:
  displayUnitsLong: OK
  displayUnitsShort: ok
  locations:
  - location-01-us-west1
  description: Measures the response code and latency to the AKS LoadBalancer Object.
  codeBundle:
    repoUrl: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    ref: main
    pathToRobot: codebundles/curl-http-ok/sli.robot
  intervalStrategy: intermezzo
  intervalSeconds: 30
  configProvided:
  - name: URL
    value: https://sampleapp.example.com
  - name: TARGET_LATENCY
    value: '1.2'
  - name: DESIRED_RESPONSE_CODE
    value: '200'
  secretsProvided: []
```



## Complex Example - Match Specific Deployments & Use Secrets

### Generation Rule

In this final example, the generation rule is configured match and render the appropriate templates for _**every Kubernetes Deployment with a specific label AND a default-container configured**_.&#x20;

```
apiVersion: runwhen.com/v1
kind: GenerationRules
spec:
  generationRules:
    - resourceTypes:
        - deployment                                          # Match Kubernetes Deployments
      matchRules:
        - type: and                                           # Require both conditions to be satisfied
          matches:
            - type: pattern
              pattern: ".+"
              properties: ["spec/template/metadata/annotations/kubectl.kubernetes.io//default-container"]
              mode: substring
              ### ^The above configuration MUST exist on the deployment.
              
            - type: pattern
              pattern: "codecollection.runwhen.com/app"
              properties: [labels]
              mode: substring
              ### ^The above label MUST exist on the deployment.  
              
      slxs:
        - baseName: k8s-tail-logs-dynamic
          qualifiers: ["resource", "namespace", "cluster"]    # Generate 1 SLX for every (matched) deployment found in every namespace in every cluster.
          baseTemplateName: k8s-tail-logs-dynamic
          levelOfDetail: detailed
          outputItems:
            - type: slx
            - type: slo
            - type: runbook
              templateName: k8s-tail-logs-dynamic-taskset.yaml
            - type: sli
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-tail-logs-dynamic/.runwhen/generation-rules/k8s-tail-logs-dynamic.yaml)

### Runboook/TaskSet Example

{% hint style="info" %}
Runbooks and TaskSets are terms that are used interchangeably. The CodeBundle code must exist in a file called runbook.robot, but we sometimes refer to this runbook.robot code as TaskSets.&#x20;
{% endhint %}

n the previous example, we outlined an SLI template that was generated for every ingress object found in every namespace & every cluster.  In this example, we will highlight the Runbook/TastkSet template that is found in the `templates` directory. The \*complete `.runwhen`directory is as follows:&#x20;

```
.runwhen
├── generation-rules
│   └── k8s-tail-logs-dynamic.yaml
└── templates
    ├── k8s-tail-logs-dynamic-sli.yaml
    ├── k8s-tail-logs-dynamic-slo.yaml
    ├── k8s-tail-logs-dynamic-slx.yaml
    └── k8s-tail-logs-dynamic-taskset.yaml
```

Since the previous example shows an SLI, this example will outline the Runbook/TaskSet template:&#x20;

```
apiVersion: runwhen.com/v1
kind: Runbook
metadata:
  name: {{slx_name}}                                      
  ### ^Always add this - it is auto generated. 
  
  labels:
    {% raw %}
{% include "common-labels.yaml" %}                    
    ### ^Always add this
    
  annotations:    
    {% include "common-annotations.yaml" %}               
    ### ^Always add this
    
spec:
  location: {{default_location}}
  codeBundle:
    {% if repo_url %}
    repoUrl: {{repo_url}}
    {% else %}
    repoUrl: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    ### ^The default url to the CodeCollection.
    
    {% endif %}
    {% if ref %}
    ref: {{ref}}
    {% else %}
    ref: main
    {% endif %}
    pathToRobot: codebundles/k8s-tail-logs-dynamic/runbook.robot
    ### ^The default path to the CodeBundle code
    
    ### ^The jijna if/else above is used to support user overrides for forks/branches/etc.
 
  configProvided:
  - name: KUBERNETES_DISTRIBUTION_BINARY
    value: kubectl
    ### ^A sensible default for the code to function.
    
  - name: LOGS_SINCE
    value: 10m
    ### ^A sensible default for the code to function.

  - name: LABELS
    value: codecollection.runwhen.com/app={{match_resource.resource.metadata.labels.get('codecollection.runwhen.com/app')}}
    ### ^The rendered value from the discovered/matched resource for the specific labels to use.
    
  - name: EXCLUDE_PATTERN
    value: INFO
  - name: CONTAINER_NAME
    value: {{match_resource.resource.spec.template.metadata.annotations.get('kubectl.kubernetes.io/default-container')}}
    ### ^The rendered value from the discovered/matched resouce for the default container.
    
  - name: MAX_LOG_LINES
    value: '500'
  - name: NAMESPACE
    value: {{match_resource.resource.metadata.namespace}}
    ### ^The rendered value from the discovered/matched resource.
    
  - name: CONTEXT
    value: {{context}}
    ### ^The rendered value from the discovered/matched resource.
    
  - name: STACKTRACE_PARSER
    value: Dynamic
    ### ^A sensible default for the code to function.
    
  - name: INPUT_MODE
    value: SPLIT
    ### ^A sensible default for the code to function.

  - name: MAX_LOG_BYTES
    value: '2560000'
    ### ^A sensible default for the code to function.

  secretsProvided:
  {% if wb_version %}
    {% include "kubernetes-auth.yaml" ignore missing %}
  {% else %}
    - name: kubeconfig
      workspaceKey: {{custom.kubeconfig_secret_name}}
  {% endif %}
{% endraw %}
  ### ^Use this when the secrets needed are for Kubernetes. These templates help
  ### substitute the right authentcation for the users environment. 
```

[Reference example](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-tail-logs-dynamic/.runwhen/templates/k8s-tail-logs-dynamic-taskset.yaml)

A fully rendered example of the above template is as follows:&#x20;

```
apiVersion: runwhen.com/v1
kind: Runbook
metadata:
  name: b-sandbox--v-va-grnsucsc1c-k8s-tl-lgs-dyn-8bc522d2
  labels:
    slx: b-sandbox--v-va-grnsucsc1c-k8s-tl-lgs-dyn-8bc522d2
    workspace: b-sandbox
  annotations:
    fullSlxName: vote-voting-app-gke-runwhen-nonprod-sandbox-us-central1-sandbox-cluster-1-cluster-k8s-tail-logs-dynamic-8bc522d2
    sourceGenerationRuleRepoURL: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    sourceGenerationRuleRepoRef: main
    sourceGenerationRulePath: codebundles/k8s-tail-logs-dynamic/.runwhen/generation-rules/k8s-tail-logs-dynamic.yaml
    config.runwhen.com/last-updated-by: workspace-builder
    qualifiers: '{''resource'': ''vote'', ''namespace'': ''voting-app'', ''cluster'':
      ''gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster''}'
spec:
  location: location-01-us-west1
  codeBundle:
    repoUrl: https://github.com/runwhen-contrib/rw-cli-codecollection.git
    ref: main
    pathToRobot: codebundles/k8s-tail-logs-dynamic/runbook.robot
  configProvided:
  - name: KUBERNETES_DISTRIBUTION_BINARY
    value: kubectl
  - name: LOGS_SINCE
    value: 10m
  - name: LABELS
    value: codecollection.runwhen.com/app=vote
  - name: EXCLUDE_PATTERN
    value: INFO
  - name: CONTAINER_NAME
    value: vote
  - name: MAX_LOG_LINES
    value: '500'
  - name: NAMESPACE
    value: voting-app
  - name: CONTEXT
    value: gke_runwhen-nonprod-sandbox_us-central1_sandbox-cluster-1-cluster
  - name: STACKTRACE_PARSER
    value: Dynamic
  - name: INPUT_MODE
    value: SPLIT
  - name: MAX_LOG_BYTES
    value: '2560000'
  secretsProvided:
  - name: kubeconfig
    workspaceKey: kubeconfig

```
