# CodeBundle Testing

## Environment Testing Flow

The common testing flow is to test locally (from your own developer environment, interacting with your test infrastructure). Once complete, if your CodeBundle contains [generation-rules](generation-rules/ "mention"), those should be tested against your test infrastructure. If that successfully generates the necsesary RunWhen Platform configurations, they can be uploaded to a RunWhen Platform Workspace for testing from the SaaS service.&#x20;

<figure><img src="../.gitbook/assets/codecollection-development-Development Flow.drawio.png" alt=""><figcaption><p>High Level CodeBundle Development Testing Flow</p></figcaption></figure>

{% hint style="info" %}
Note: The screenshots and code used in this example has been provided from an Azure specific CodeBundle that uses the `az` cli for client authentication. References to secrets and specific configuration data will vary depending on the CodeBundle purpose.
{% endhint %}



## Testing Tools

### RO (Robot CLI)

The `ro` cli utility is a very simple wrapper for the running robot files with a standardized output folder, which ensures that output files are:&#x20;

* not committed to source code
* easily accessible from your development environment and the local server on port 3000

#### **Running sli/runbook code with `ro`**

The `ro` cli can be involked from within the CodeBundle folder:&#x20;

```
~/rw-cli-codecollection/codebundles/azure-aks-triage$ ro sli.robot 
==============================================================================
Sli :: Checks AKS Configuration and returns a 1 when healthy, or 0 when not...
==============================================================================
Check for Resource Health Issues Affecting AKS Cluster `aks-cl-1` ... .
.....
------------------------------------------------------------------------------
Sli :: Generates a composite score about the health of an AKS clus... | PASS |
4 tasks, 4 passed, 0 failed
==============================================================================
Output:  /workspace/robot_logs/sli-output.xml
Log:     /workspace/robot_logs/sli-log.html
Report:  /workspace/robot_logs/sli-report.html
```

#### **Accessing detailed trace logs**

When running sli.robot and runbook.robot files, the detailed trace log output is a crucial tool in the development workflow, assisible through http://0.0.0.0:3000 (or whichever port CodeSpaces or equivalent development environment exposes).&#x20;

<figure><img src="../.gitbook/assets/image (7).png" alt=""><figcaption><p>Reviewing Robot Trace Logs</p></figcaption></figure>

### Task (taskfile.dev)

Most RunWhen Authors have started to leverage Taskfiles for managing testing tasks. CodeBundles should be self-contained in their own folders, and ideally with a `.test` subfolder that contains helpful Taskfiles. These are intended to:&#x20;

* speed up testing within your own infrastructure
* assist others in reproducing the test scenario (if trying to validate or improve the CodeBundles)

&#x20;Each Taskfile may differ from one another depending on the infrastructure components that the CodeBundle supports and is tested against. For example, one such Taskfile might have the following tasks related to setting up and tearing down Terraform infrastructure to build an AKS cluster:&#x20;

```
~/rw-cli-codecollection/codebundles/azure-aks-triage/.test$ task -l 
task: Available tasks for this project:
* build-infra:                       Build test infrastructure
* build-terraform-infra:             Run terraform apply
* check-and-cleanup-terraform:       Check and clean up deployed Terraform infrastructure if it exists
* check-terraform-infra:             Check if Terraform has any deployed infrastructure in the terraform subdirectory
* check-unpushed-commits:            Check if outstanding commits or file updates need to be pushed before testing.
* clean:                             Run cleanup tasks
* clean-rwl-discovery:               Check and clean up RunWhen Local discovery output
* cleanup-terraform-infra:           Cleanup deployed Terraform infrastructure
* default:                           Run/refresh config
* delete-slxs:                       Delete SLX objects from the appropriate URL
* generate-rwl-config:               Generate RunWhen Local configuration (workspaceInfo.yaml)
* run-rwl-discovery:                 Run RunWhen Local Discovery on test infrastructure
* upload-slxs:                       Upload SLX files to the appropriate URL
* validate-generation-rules:         Validate YAML files in .runwhen/generation-rules
```

As you can see, there are a number of helpful tasks here, some of which might be easily portable across multiple CodeBundles (such as `upload-slxs` or `delete-slxs`), some which require minor adjustment from one CodeBundle to the next (such as `generate-rwl-config` ) and others which might not apply at all (such as `build-terraform-infra`  or `cleanup-terraform-infra` if the infrastructure uses a different provisioning mechanism).&#x20;

For this reason, existing Taskfiles should be reviewed and a README.MD should be updated so that other users can leverage them effectively.&#x20;

## Local Testing

### CodeBundle Testing

Once the appropriate test infrastructure has been deployed, most local testing is performed by setting the necessary environment variables and authentication steps, followed by using the `ro` utility to run the `sli.robot` or `runbook.robot` files. All required environment variables and authentication prerequisites should be documentd in the CodeBundle `README.md`.&#x20;

Once the code is functioning as expected, [generation-rules](generation-rules/ "mention")can be created (if appropriate).&#x20;

### Generation Rule Testing

RunWhen Local can be easily used to test your CodeBundle Generation Rules if it contains the following:

* a `.runwhen` folder with at least one Generation Rule and corresponding templates
* a .test/Taskfile with `generate-rwl-config` and `run-rwl-discovery`

These tasks will generate a RunWhen Local configuration file that uses your CodeBundle and your test infrastructure to generate configuration. This will create a `workspaceInfo.yaml` file as well as an `output` directory with the generated configuration files. These generated files are in the `.gitignore` and will not be uploaded to your CodeCollection.&#x20;

To run the task:&#x20;

```
~/rw-cli-codecollection/codebundles/azure-aks-triage/.test $ task
Checking for uncommitted changes in  and .runwhen, excluding '.test'...
√
No uncommitted changes in specified directories.
------------
Checking for unpushed commits in  and .runwhen, excluding '.test'...
√
No unpushed commits in specified directories.
------------
Stopping and removing existing container RunWhenLocal...
Cleaning up output directory...
Starting new container RunWhenLocal...
b4c2039c8b6690b8d596b1871b72395392d6bb2400e5e458e050a1cf22ae4c3a
Running workspace builder script in container...
Workspace builder REST service isn't available yet; waiting and trying again.
Workspace builder version: 0.7.4
...
Discovery started at: 2024-11-04 22:06:37 
Discovering resources...
Workspace builder completed successfully.
Starting cheat sheet rendering...
Cheat sheet rendering completed.

Review generated config files under output/workspaces/
```

```
~/rw-cli-codecollection/codebundles/azure-aks-triage/.test $ tree 
.
├── output
│   ├── resource-dump.yaml
│   └── workspaces
│       └── [workspace-name]
│           ├── slxs
│           │   └── ac1-aa-az-aks-triage-ac6325d3
│           │       ├── runbook.yaml
│           │       ├── sli.yaml
│           │       └── slx.yaml
│           └── workspace.yaml
├── README.md
├── Taskfile.yaml
└── workspaceInfo.yaml


```

### Uploading SLXs to the RunWhen Platform

Most Taskfiles also include the option to `upload-slxs` and `delete-slxs`once the SLX configuration files have been reviewed for accuracy, they can be uploaded to the RunWhen Platform for further testing. &#x20;

## RunWhen Platform Workspace Testing

Once the configuration data has been reviewed, they can be uploaded to a RunWhen Platform workspace if the `upload-slxs` and `delete-slxs` tasks exist in your Taskfile, and the following environment variables have been set:&#x20;

* RW\_API\_URL="papi.beta.runwhen.com"
* RW\_WORKSPACE="\[your-runwhen-platform-workspace-name]"
* RW\_PAT="\[your-personal-access-token]"

```
~/rw-cli-codecollection/codebundles/azure-aks-triage/.test$ task upload-slxs
Uploading SLX: ac1-aa-az-aks-triage-ac6325d3 to https://papi.test.runwhen.com/api/v3/workspaces/t-shea-ws-03/branches/main/slxs/ac1-aa-az-aks-triage-ac6325d3
Successfully uploaded SLX: ac1-aa-az-aks-triage-ac6325d3 to https://papi.test.runwhen.com/api/v3/workspaces/t-shea-ws-03/branches/main/slxs/ac1-aa-az-aks-triage-ac6325d3
```

{% hint style="info" %}
If the upload to the RunWhen Platform fails, feel free to contact our team. There are often validation errors that might occur but which aren't easy to surface in the failure response. Most often a configProvided value is an `integer` instead of a `string`, but other errors may not be so obvoious.&#x20;
{% endhint %}

Within a few minutes, the new SLX(s) will be available in the RunWhen Workspace Map

<figure><img src="../.gitbook/assets/image (8).png" alt=""><figcaption><p>Viewing a newly uploaded SLX</p></figcaption></figure>

### Updating Secrets

While the SLI will start attempting to run immediately, you may need to select the "Edit" option on the SLX to update the Secrets configuration. In many cases, you may have Secrets configured in your Workspace for testing which won't immediately line up with the SLX configuration.

<figure><img src="../.gitbook/assets/image (9).png" alt=""><figcaption><p>Editing the SLX Configuration</p></figcaption></figure>

<figure><img src="../.gitbook/assets/image (10).png" alt=""><figcaption><p>Editing the SLI secretsProvided</p></figcaption></figure>

The above screenshot outlines the secretsProvided configuration to point at a RunWhen Managed secret, which can be added/updated through **Configuration -> Secrets**



### Validating Health and Tasks

When the secrets are updated, the Health and Tasks should be tested:&#x20;

<figure><img src="../.gitbook/assets/image (1) (1).png" alt=""><figcaption><p>Viewing SLI / Health</p></figcaption></figure>

<figure><img src="../.gitbook/assets/image (1) (1) (1).png" alt=""><figcaption><p>Creating a RunSession with all Tasks</p></figcaption></figure>

<figure><img src="../.gitbook/assets/image (2) (1).png" alt=""><figcaption><p>Reviewing RunSession Report</p></figcaption></figure>
