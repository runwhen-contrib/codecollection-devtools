# RunWhen Keywords

### Running Bash and CLI Commands

#### RW.Core.Create RunWhen Temp Dir

* Most often Used in `Suite Setup`or `Suite Initialization`Tasks
* Creates a temporary directory and sets the Suite Variable `${RUNWHEN_TEMP_DIR}` with the value of the path
* Can easily be used to store/retrieve files or ouput for Task usage
* May automatically be cleaned up between Task runs



Example Usage

```robotframework
Suite Setup         Suite Initialization
Suite Teardown      Suite Teardown

*** Keywords ***
Suite Initialization
    RW.Core.Create RunWhen Temp Dir
    

*** Keywords ***
Run Kubectl CLI Command
    [Documentation]    Run Command and Store Output
    [Tags]    cli    kubectl    access:read-only
    ${response}=    RW.CLI.Run Cli
    ...    cmd=kubectl get pods -o json -A > ${RUNWHEN_TEMP_DIR}/pods.json
    ...    env=${env}
    ...    secret_file__kubeconfig=${kubeconfig}

```

Related Keywords

* `RW.Core.Create RunWhen Temp Dir`
* Often used in `Suite Teardown`

Example Usage

```
Suite Teardown   
    RW.Core.Remove RunWhen Temp Dir

```
