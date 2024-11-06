---
description: >-
  This guide quickly gets you up and running using the repository template, the
  devtools container image, and a few basic CodeBundle tests.
---

# Getting Started

## CodeCollection Development Environment Setup

### Repository Initialization

To get started, first create a CodeCollection using the repository [template ](https://github.com/runwhen-contrib/codecollection-template)on GitHub. Select the `Create a new repository` option from the `Use this template` dropdown.

<figure><img src="../.gitbook/assets/image (11).png" alt=""><figcaption><p>Creating a CodeCollection Repository from Template</p></figcaption></figure>

<figure><img src="../.gitbook/assets/image (13).png" alt=""><figcaption><p>Example CodeCollection Repository</p></figcaption></figure>

### Start Your Development In CodeSpaces

With your template created you'll be able to run it in codespaces. (or locally using the devcontainer VSCode plugin) On the readme of your new repository you'll see a badge titled `Open in GitHub Codespaces` - clicking that will start up a codespace for you.

<figure><img src="../.gitbook/assets/image (14).png" alt=""><figcaption></figcaption></figure>

You'll be greeted with a VS Code editor in your browser like this:

<figure><img src="../.gitbook/assets/image (16).png" alt=""><figcaption></figcaption></figure>

#### Open Your Development Environment in VS Code

If running in Visual Studio Code, clone the repository and upon opening the repo, access the Command Pallet (Ctrl + Shift +P) and select "Dev Containers: Reopen folder to develop in a Container"

<figure><img src="../.gitbook/assets/image (17).png" alt=""><figcaption><p>Opening the the devcontainer locally in vscode</p></figcaption></figure>





### Validate CodeBundle Functionality

To ensure that the environment is functioning, run the hello world CodeBundle. Use the `ro` cli utility, which is just a simple wrapper for running robot, to run the sli.robot file.&#x20;

```
runwhen@codespaces-29ff86:~/codecollection/$ cd codebundles/hello_world
runwhen@codespaces-29ff86:~/codecollection/codebundles/hello_world$ ro sli.robot 
==============================================================================
Sli :: This is a hello world codebundle!                                      
==============================================================================
Hello World                                                           ..
Push metric: value:1 sub_name:None metric_type:untyped labels:{}

Hello World                                                           | PASS |
------------------------------------------------------------------------------
Sli :: This is a hello world codebundle!                              | PASS |
1 task, 1 passed, 0 failed
==============================================================================
Output:  /robot_logs/sli-output.xml
Log:     /robot_logs/sli-log.html
Report:  /robot_logs/sli-report.html
runwhen@codespaces-29ff86:~/codecollection/codebundles/hello_world$ 
```

To view the detailed log output, you can select the Ports tab and open port 3000 in the browser:&#x20;

<figure><img src="../.gitbook/assets/image (19).png" alt=""><figcaption><p>Accessing the HTTP Log Server</p></figcaption></figure>

<div align="left" data-full-width="false">

<figure><img src="../.gitbook/assets/image (20).png" alt=""><figcaption><p>Viewing the HTTP Log Server Directories</p></figcaption></figure>

</div>

<figure><img src="../.gitbook/assets/image (22).png" alt=""><figcaption><p>Viewing Robot Logs</p></figcaption></figure>



