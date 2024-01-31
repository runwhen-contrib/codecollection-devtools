**Understand robot framerowk script with and example**

repository is ready now introduce runbook.robot file to run a bash file. 

In this script, a Bash file is invoked to terminate specific processes in MySQL, involving environment variables and two secrets.

```
*** Settings ***
Documentation       This taskset Kills the numbers of sleep process created in MySQL
Metadata            Author    IFC

Library             BuiltIn
Library             RW.Core
Library             RW.platform
Library             RW.CLI

Suite Setup         Suite Initialization

*** Tasks ***
Run Bash File
    [Documentation]    Runs a bash file to kill sleep processes created in MySQL
    [Tags]    file    script
    ${rsp}=    RW.CLI.Run Bash File
    ...    bash_file=kill-mysql-sleep-processes.sh
    ...    cmd_override=./kill-mysql-sleep-processes.sh
    ...    env=${env}
    ...    secret__mysql_password=${MYSQL_PASSWORD}
    ...    secret__mysql_host=${MYSQL_HOST}
    ...    include_in_history=False
    RW.Core.Add Pre To Report    Command Stdout:\n${rsp.stdout}
    RW.Core.Add Pre To Report    Command Stderr:\n${rsp.stderr}

*** Keywords ***
Suite Initialization
   ${MYSQL_PASSWORD}=    RW.Core.Import Secret   MYSQL_PASSWORD
    ...    type=string
    ...    description=MySQL password
    ...    pattern=\w*
    ...    example='9jZGIzNDIxego'
    ${MYSQL_USER}=    RW.Core.Import User Variable    MYSQL_USER
    ...    type=string
    ...    description=MySQL Username
    ...    pattern=\w*
    ...    example=admin
    ${MYSQL_HOST}=    RW.Core.Import Secret   MYSQL_HOST
    ...    type=string
    ...    description=MySQL host endpoint
    ...    pattern=\w*
    ...    example=exdb.example.us-west-2.rds.amazonaws.com
    ${PROCESS_USER}=    RW.Core.Import User Variable    PROCESS_USER
    ...    type=string
    ...    description=mysql user which created numbers of sleep connections
    ...    pattern=\w*
    ...    example=shipping

    Set Suite Variable
    ...    ${env}    {"MYSQL_USER":"${MYSQL_USER}", "PROCESS_USER":"${PROCESS_USER}"}

```

In the Set Suite Variable section, a map of variables is created and assigned to `${env}`, which is then passed to `RW.CLI.Run Bash File`. `RW.CLI` library exports these variables for `kill-mysql-sleep-processes.sh`.

Environment variables and secretcan be passed using Docker env with the -e flag. The same applies to secrets.

For secrets, a pattern of `secret__<variable name>` is observed (e.g., `secret__mysql_password`). The prefix `secret__` instructs `RW.CLI.Run Bash File` function to unmask the secret and pass it as the MYSQL_PASSWORD environment variable.
