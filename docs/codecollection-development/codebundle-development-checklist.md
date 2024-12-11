# CodeBundle Development Checklist

The items in this list should be reviewed when releasing a CodeBundle for general use. These are less about CodeBundle functionality (which should be thoroughly tested), and more about basic linting checks. This list will eventually be converted into an automated tool.&#x20;

## Basic Checks

* **Settings**
  * Documentation - A basic description of the CodeBundle functionality
  * Metadata
    * Author - A GitHub username of the author
    * Display Name - The "pretty name" of the CodeBundle
    * Supports - All of the platforms/technologies/languages that this CodeBundle Supports
  * Suite Setup - The keyword that is called before any Task runs

```
*** Settings ***
Documentation       Triages issues related to a deployment and its replicas.
Metadata            Author    stewartshea
Metadata            Display Name    Kubernetes Deployment Triage
Metadata            Supports    Kubernetes,AKS,EKS,GKE,OpenShift

Suite Setup         Suite Initialization

```

Much of this data helps display details about the CodeBundle within the platform and in the [Registry](https://registry.runwhen.com)

{% embed url="https://registry.runwhen.com/CodeCollection/rw-cli-codecollection/k8s-deployment-healthcheck/tasks/" %}

* **Suite Setup**
  * Import User Variables - Import all non-senseitive configuration values
  * Import User Secrets  - Import sensitive data / configuration values
  * Set Suite Variable - Set all imported or required user variables for all Tasks

```
*** Keywords ***
Suite Initialization
    ${kubeconfig}=    RW.Core.Import Secret
    ...    kubeconfig
    ...    type=string
    ...    description=The kubernetes kubeconfig yaml containing connection configuration used to connect to cluster(s).
    ...    pattern=\w*
    ...    example=For examples, start here https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
    ${DEPLOYMENT_NAME}=    RW.Core.Import User Variable    DEPLOYMENT_NAME
    ...    type=string
    ...    description=Used to target the resource for queries and filtering events.
    ...    pattern=\w*
    ...    example=artifactory
    ${NAMESPACE}=    RW.Core.Import User Variable    NAMESPACE
    ...    type=string
    ...    description=The name of the Kubernetes namespace to scope actions and searching to.
    ...    pattern=\w*
    ...    example=my-namespace
    ${CONTEXT}=    RW.Core.Import User Variable    CONTEXT
    ...    type=string
    ...    description=Which Kubernetes context to operate within.
    ...    pattern=\w*
    ...    example=my-main-cluster
    Set Suite Variable    ${kubeconfig}    ${kubeconfig}
    Set Suite Variable    ${KUBERNETES_DISTRIBUTION_BINARY}    ${KUBERNETES_DISTRIBUTION_BINARY}
    Set Suite Variable    ${CONTEXT}    ${CONTEXT}
    Set Suite Variable    ${NAMESPACE}    ${NAMESPACE}
    Set Suite Variable    ${DEPLOYMENT_NAME}    ${DEPLOYMENT_NAME}
```

* **Tasks**
  * Documentation - describes the specific task function
  * Tags - additional tags that help with indexing of the tasks
  * &#x20;`RW.Core.Add Pre To Report` - For TaskSets / runbook.robot files, content must be added to the report with this keyword.&#x20;
  * `RW.Core.Push Metric` -  For Health / sli.robot files, a metric is pushed back to the RunWhen platform with this keyword

```
*** Tasks ***
Check Deployment Log For Issues with `${DEPLOYMENT_NAME}`
    [Documentation]    Fetches recent logs for the given deployment in the namespace and checks the logs output for issues.
    [Tags]
    ...    fetch
    ...    log
    ...    pod
    ...    container
    ...    errors
    ...    inspect
    ...    trace
    ...    info
    ...    deployment
    ...    ${DEPLOYMENT_NAME}
    ${logs}=    RW.CLI.Run Bash File
    ...    bash_file=deployment_logs.sh 
    ...    cmd_override=./deployment_logs.sh | tee "${SCRIPT_TMP_DIR}/log_analysis"
    ...    env=${env}
    ...    secret_file__kubeconfig=${kubeconfig}
    ...    timeout_seconds=180
    ...    include_in_history=false
    ${history}=    RW.CLI.Pop Shell History
    RW.Core.Add Pre To Report
    ...    Recent logs from Deployment ${DEPLOYMENT_NAME} in Namespace ${NAMESPACE}:\n\n${logs.stdout}
    RW.Core.Add Pre To Report    Commands Used: ${history}
```

## Advanced Checks

### Issues & Next Steps

The power of RunWhen CodeBundles comes in with **Issues** and **Next Steps.** A Task can raise an Issue that provides specific detail to either a RunWhen Engineering Assistant, or for a service owner to review for further action. &#x20;

* Issues
  * Severity - 1 - Critical, 2 = Error / Major, 3 = Warning/Minor, 4 = Informational
  * Expected - The expected state from the Task
  * Actual -  The actual state from the Task&#x20;
  * Title - The title of the issue, with emphasis on details about _What_ and _Where_&#x20;
  * Reproduce Hint - A string, or reference to the command, that was used to determine this result.
  * Details - Specific details about the issue. Usually a subset of the data that is posted in the report.&#x20;
  * Next Steps - A `\n` deliminted list of suggested next steps. These should often look like another Task that may exist in a workspace. If someone came to you with this issue, what would you suggest they do next?&#x20;

Issues can be simple, advanced, or complex.&#x20;

#### Simple Issues

A simple issue may provide very direct and static content, for example:&#x20;

```
        RW.Core.Add Issue    title=Errors in Flux Controller Reconciliation
        ...    severity=3
        ...    expected=No errors in Flux controller reconciliation.
        ...    actual=Flux controllers have errors in their reconciliation process.
        ...    reproduce_hint=Run flux_reconcile_report.sh manually to see the errors.
        ...    next_steps=Inspect Flux logs to determine which objects are failing to reconcile.
        ...    details=${process.stdout}
```

{% embed url="https://registry.runwhen.com/CodeCollection/rw-cli-codecollection/k8s-fluxcd-reconcile/tasks/" %}

{% embed url="https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-fluxcd-reconcile/runbook.robot#L25-L33" %}

#### Advanced Issues

This simple example is easy to extend in another example where the severity and title may change:&#x20;

```
    IF    $deployment_status["available_condition"]["status"] == "False" or $deployment_status["ready_replicas"] == "0"
        ${item_next_steps}=    RW.CLI.Run Bash File
        ...    bash_file=workload_next_steps.sh
        ...    cmd_override=./workload_next_steps.sh "${deployment_status["available_condition"]["message"]}" "Deployment" "${DEPLOYMENT_NAME}"
        ...    env=${env}
        ...    include_in_history=False
        RW.Core.Add Issue
        ...    severity=1
        ...    expected=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` should have minimum availability / pod.
        ...    actual=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` does not have minimum availability / pods.
        ...    title= Deployment `${DEPLOYMENT_NAME}` in Namespace `${NAMESPACE}` is unavailable
        ...    reproduce_hint=View Commands Used in Report Output
        ...    details=Deployment `${DEPLOYMENT_NAME}` has ${deployment_status["ready_replicas"]} ready pods and needs ${deployment_status["desired_replicas"]}:\n`${deployment_status}`
        ...    next_steps=${item_next_steps.stdout}
    ELSE IF    $deployment_status["unavailable_replicas"] > 0 and $deployment_status["available_condition"]["status"] == "True" and $deployment_status["progressing_condition"]["status"] == "False"
        RW.Core.Add Issue
        ...    severity=3
        ...    expected=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` should have ${deployment_status["desired_replicas"]} pods.
        ...    actual=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` has ${deployment_status["ready_replicas"]} pods.
        ...    title= Deployment `${DEPLOYMENT_NAME}` in Namespace `${NAMESPACE}` has less than the desired availability
        ...    reproduce_hint=View Commands Used in Report Output
        ...    details=Deployment `${DEPLOYMENT_NAME}` has minimum availability, but has unready pods:\n`${deployment_status}`
        ...    next_steps=Inspect Deployment Warning Events for `${DEPLOYMENT_NAME}`
    END
    IF    $deployment_status["desired_replicas"] == 1
        RW.Core.Add Issue
        ...    severity=4
        ...    expected=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` should have more than 1 desired pod.
        ...    actual=Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}` is configured to have only 1 pod.
        ...    title= Deployment `${DEPLOYMENT_NAME}` in Namespace `${NAMESPACE}` is not configured to be highly available.
        ...    reproduce_hint=View Commands Used in Report Output
        ...    details=Deployment `${DEPLOYMENT_NAME}` is only configured to have a single pod:\n`${deployment_status}`
        ...    next_steps=Get Deployment Workload Details For `${DEPLOYMENT_NAME}` and Add to Report\nAdjust Deployment `${DEPLOYMENT_NAME}` spec.replicas to be greater than 1.
    END
```

{% embed url="https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-deployment-healthcheck/runbook.robot#L248-L282" %}

#### Complex Issues

A much more advanced approach is to provide dynamic issue details depending on the output of the script or code that identified the problem, for example:&#x20;

```
    
    ${recommendations}=    RW.CLI.Run Cli
    ...    cmd=echo '${container_restart_analysis.stdout}' | awk '/Recommended Next Steps:/ {flag=1; next} flag'
    ...    env=${env}
    ...    include_in_history=false
    IF    $recommendations.stdout != ""
        ${recommendation_list}=    Evaluate    json.loads(r'''${recommendations.stdout}''')    json
        IF    len(@{recommendation_list}) > 0
            FOR    ${item}    IN    @{recommendation_list}
                RW.Core.Add Issue
                ...    severity=${item["severity"]}
                ...    expected=Containers should not be restarting for Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}`
                ...    actual=We found containers with restarts for Deployment `${DEPLOYMENT_NAME}` in namespace `${NAMESPACE}`
                ...    title=${item["title"]}
                ...    reproduce_hint=${container_restart_analysis.cmd}
                ...    details=${item["details"]}
                ...    next_steps=${item["next_steps"]}
            END
        END
    END
```

{% embed url="https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/k8s-deployment-healthcheck/runbook.robot#L84-L97" %}
