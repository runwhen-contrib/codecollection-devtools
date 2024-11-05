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



#### Open Your Development Environment in VS Code

If running in Visual Studio Code, clone the repository and upon opening the repo, select "Reopen folder to develop in a Container"

<figure><img src="../.gitbook/assets/image (15).png" alt=""><figcaption></figcaption></figure>



### Test a Basic CodeBundle

To ensure that the environment is functioning, run the hello world CodeBundle. Use the `ro` cli utility, which is just a simple wrapper for running robot, to run the sli.robot file.&#x20;

```
cd codecollection/codebundles/hello_world
ro sli.robot
```

<figure><img src="../.gitbook/assets/4.png" alt=""><figcaption><p>Hello World Code Bundle</p></figcaption></figure>

Success! Seeing a pass means the robot file completed without raising uncaught exceptions. You'll notice there's some log output as well. We can view them in a neat UI thanks to an HTTP server running in the devcontainer.

<figure><img src="../.gitbook/assets/5.png" alt=""><figcaption><p>Accessing the HTTP Server for Code Bundle Trace Logs</p></figcaption></figure>

Going to the authenticated URL, we can then view the robot logs which are nicely formated for us to browse:

<figure><img src="../.gitbook/assets/6.png" alt=""><figcaption><p>Viewing the Robot Trace Logs</p></figcaption></figure>

Congrats on running your first Code Bundle!

{% hint style="info" %}
If you don't want to use VSCode or Codespaces, your new repo has a built image that you can develop in!
{% endhint %}

```
docker run -d -p 3000:3000 --name mycodecollection ghcr.io/<your_name>/<repo>:latest
```
