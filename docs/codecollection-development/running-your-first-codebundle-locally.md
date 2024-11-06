# CodeBundle Basics

{% hint style="info" %}
Please see [running-your-first-codebundle.md](running-your-first-codebundle.md "mention")before referencing this page.&#x20;
{% endhint %}

## Types of CodeBundles

There are two primary CodeBundles:&#x20;

* &#x20;Service Level Indicator (SLI)
* TaskSet (Runbook)

Each of these CodeBundles is represented in a single `.robot` file, which constists of `Tasks` to perform, along with user-provided `Variables` and dependent `Libraries` that are used to support the execution of each `Task`.&#x20;

<figure><img src="../.gitbook/assets/codecollection-development.drawio.svg" alt=""><figcaption><p>CodeBundle  Types</p></figcaption></figure>

### Service Level Indicator CodeBundles

The Service Level Indicate CodeBundle can be described as follows:&#x20;

* written in the `sli.robot` file
* runs on a scheduled basis, for example, every 30 or 60 seconds
* is primarily responsible for fetching or generating a metric that is pushed to the RunWhen Platform
* these metrics can be used to trigger alerts or assist in SLO calculations

For example, a simple SLI CodeBundle might have a task that counts the number of unready pods in a namespace, and then pushes that total value to the RunWhen Platform. That number can then be used to trigger an alert if more than 1 pod us unready.

### TaskSet CodeBundles

The TaskSet CodeBundle can be describe as follows:&#x20;

* written in the `runbook.robot` file, typically with multiple Tasks
* runs on-demand, for example, when manually executed by a user, or automatically executed from an Engineering Assistant or workflow  (triggered from an alert, webhook, or some other event)
* is primarily responsible for fetching information, adding details to a report, generating high-quality `Issues` and `Next Steps` for handoff to an Engineering Assistant or human escalation

For example, related to the previous SLI use case, the TaskSet CodeBundle would have 1 Task that identifies which deployments have unready pods in the namespace, another Task might fetch a list of events related to each specific unready pod, which can then raise an `Issue` about the deployment (e.g. Deployment 'cartservice' has unready pods) with some `Next Steps` that are related to the identified events (e.g. Add resource to cluster. Could not schedule pod due to capacity limits).&#x20;

## CodeBundle Structure

This section looks at a [basic CodeBundle](https://github.com/runwhen-contrib/rw-cli-codecollection/blob/main/codebundles/curl-http-ok/sli.robot) to review each core component.&#x20;

### Settings

The **Settings** section specifies the documentation, metadata, and required libraries.&#x20;

* **Documentation**: Provides a brief summary of the taskset.
* **Metadata**:
  * **Author**: The author's name (`stewartshea`).
  * **Display Name**: The taskset’s display name (`cURL HTTP OK`).
  * **Supports**: Specifies supported operating systems (`Linux`, `macOS`, `Windows`) and protocols (`HTTP`).
* **Library**:
  * **BuiltIn**: Imports Robot Framework’s built-in functions.
  * **RW.Core**: Imports the core RunWhen library for custom functionalities.
  * **RW.CLI**: Provides CLI (Command Line Interface) capabilities within the RunWhen platform.
  * **RW.platform**: Allows platform-specific interactions within the taskset.
* **Suite Setup**: Defines a suite-wide setup step to initialize variables and configurations used across tasks

```
*** Settings ***
Documentation       This taskset uses curl to validate the response code of the endpoint. Returns ascore of 1 if healthy, an 0 if unhealthy. 
Metadata            Author    stewartshea
Metadata            Display Name    cURL HTTP OK
Metadata            Supports    Linux macOS Windows HTTP
Library             BuiltIn
Library             RW.Core
Library             RW.CLI
Library             RW.platform


Suite Setup         Suite Initialization
```

### Keywords

#### Suite Initialization

Initializes the suite by importing and setting up the necessary user-defined variables for this taskset.

* **URL**: The endpoint URL to be checked.
  * **Type**: `string`
  * **Description**: Specifies the URL to perform HTTP requests against.
  * **Default**: `https://www.runwhen.com`
* **TARGET\_LATENCY**: Maximum allowable latency (in seconds).
  * **Type**: `string`
  * **Description**: The maximum response time in seconds allowed for requests.
  * **Default**: `1.2`
* **DESIRED\_RESPONSE\_CODE**: Expected HTTP response code indicating success.
  * **Type**: `string`
  * **Description**: The response code that represents a successful response.
  * **Default**: `200`

```
*** Keywords ***
Suite Initialization
    ${URL}=    RW.Core.Import User Variable    URL
    ...    type=string
    ...    description=What URL to perform requests against.
    ...    pattern=\w*
    ...    default=https://www.runwhen.com
    ...    example=https://www.runwhen.com
    ${TARGET_LATENCY}=    RW.Core.Import User Variable    TARGET_LATENCY
    ...    type=string
    ...    description=The maximum latency in seconds as a float value allowed for requests to have.
    ...    pattern=\w*
    ...    default=1.2
    ...    example=1.2
    ${DESIRED_RESPONSE_CODE}=    RW.Core.Import User Variable    DESIRED_RESPONSE_CODE
    ...    type=string
    ...    description=The response code that indicates success.
    ...    pattern=\w*
    ...    default=200
    ...    example=200
```



### Tasks

A list of tasks to execute. Each task should be able to execute indepenent of each other.&#x20;

#### Checking HTTP URL Is Available And Timely

This task validates that the specified URL is available and meets the desired response criteria.

* **Documentation**: Uses `curl` to validate the HTTP response and check endpoint latency.
* **Tags**: `cURL`, `HTTP`, `Ingress`, `Latency`, `Errors`

Steps:

1. **Run cURL Command**:
   * Executes a `curl` command against the URL.
   * Outputs a JSON-like string with `http_code` (status code) and `time_total` (response time).
2. **Parse Response**:
   * Uses `json.loads` to parse the JSON output from `curl`.
   * Extracts `time_total` (latency) and `http_code` (HTTP status code).
3. **Evaluate Conditions**:
   * **Latency Check**: Checks if the latency is within the target value (`TARGET_LATENCY`), returning `1` if true, otherwise `0`.
   * **Status Code Check**: Validates if the HTTP status code matches the desired response code (`DESIRED_RESPONSE_CODE`), returning `1` if true, otherwise `0`.
4. **Score Calculation**:
   * Combines the latency and status code checks to produce a final score.
   * **Score**: `1` if both checks pass, otherwise `0`.
5. **Push Metric**:
   * Pushes the resulting score to the RunWhen platform as a metric.

```
*** Tasks ***
Checking HTTP URL Is Available And Timely
    [Documentation]    Use cURL to validate the http response  
    [Tags]    cURL    HTTP    Ingress    Latency    Errors
    ${curl_rsp}=    RW.CLI.Run Cli
    ...    cmd=curl -o /dev/null -w '{"http_code": \%{http_code}, "time_total": \%{time_total}}' -s ${URL}
    ${json}=    evaluate  json.loads($curl_rsp.stdout)
    ${latency}=    Set Variable    ${json['time_total']}
    ${latency_within_target}=    Evaluate    1 if ${latency} <= ${TARGET_LATENCY} else 0
    ${status_code}=    Set Variable    ${json['http_code']}
    ${http_ok}=    Evaluate    1 if ${status_code} == ${DESIRED_RESPONSE_CODE} else 0
    ${score}=    Evaluate    int(${latency_within_target}*${http_ok})
    RW.Core.Push Metric    ${score}
```

## RunWhen Development Tools

The devtools container image contains some development tools that help with local testing and replicate platform functionality. One such example is the ability to pull in an Environment Variable as a Secret for use with the CodeBundle. The following list of developer interfaces or environment variables can be used during local development.&#x20;

### Environment Variables

#### RW\_FROM\_FILE

For some secrets you may wish to store them in files rather than environment variables(json service accounts are a good example). The devtools container contains an `/~/auth/` directory ( which is gitignored) for storing secret files during development. In order to tell the environment to pull in secrets from a specific file, set the environment variable with a file mapping, such as: &#x20;

* Local Environment Configuration

`export RW_FROM_FILE='{"kubeconfig":"/home/runwhen/auth/kubeconfig"}'`

* Usage in a CodeBundle

```
*** Keywords ***
Suite Initialization
    ${kubeconfig}=    RW.Core.Import Secret     kubeconfig
    ...    type=string
    ...    description=The kubeconfig secret to use for authenticating with the cluster.
    ...    pattern=\w*
```

#### RW\_SECRET\_REMAP

If you're working with multiple similar secrets and wish to avoid constantly re-exporting them, you can remap them by setting this environment variable:

`RW_SECRET_REMAP='{"kubeconfig":"MY_KUBECONFIG"}'`

This will cause all instances of `kubeconfig` to use `MY_KUBECONFIG` when the CodeBundle imports a secret called `kubeconfig`

#### RW\_ENV\_REMAP

Similar to the secret name remap, you can do the same for environment variables to avoid re-exporting them:

`RW_ENV_REMAP='{"PROMETHEUS_HOSTNAME":"PROM_HOSTNAME"}'`
