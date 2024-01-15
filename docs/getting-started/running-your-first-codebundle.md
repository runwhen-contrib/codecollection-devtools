---
description: This page will walk you through running your first codebundle via Codespaces
---

# Running Your First Codebundle

### Setup Your Repository :book:

To run your first codebundle we'll first create a codecollection for it to live in. Head over to our [template ](https://github.com/runwhen-contrib/codecollection-template)on github and select the `Create a new repository` option from the `Use this template` dropdown. You can name your template whatever you like.

<figure><img src="../../.gitbook/assets/image (11).png" alt=""><figcaption><p>Template Setup</p></figcaption></figure>

### Launch it :rocket:

With your template created you'll be able to run it in codespaces. (or locally using the devcontainer VSCode plugin) On the readme of your new repository you'll see a badge titled `Open in GitHub Codespaces` - clicking that will start up a codespace for you.

<figure><img src="../../.gitbook/assets/image (12).png" alt=""><figcaption><p>Readme</p></figcaption></figure>

You'll be greated with a VSCode editor in your browser like this

<figure><img src="../../.gitbook/assets/image (13).png" alt=""><figcaption><p>VSCode</p></figcaption></figure>

### Run it! :man\_running:

Running a codebundle is easy! There's a script`ro` in the devtools container that handles the complicated stuff for you, so we can run any robot file with`ro <robot filename>`

```
cd codecollection/codebundles/hello_world
ro sli.robot
```

<figure><img src="../../.gitbook/assets/image (17).png" alt=""><figcaption><p>Hello World Codebundle</p></figcaption></figure>

Success! Seeing a pass means the robot file completed without raising uncaught exceptions. You'll notice there's some log output as well. We can view them in a neat UI thanks to an HTTP server running in the devcontainer.&#x20;

<figure><img src="../../.gitbook/assets/devtools.png" alt=""><figcaption><p>VSCode Open HTTP Server</p></figcaption></figure>

Going to the authenticated URL, we can then view the robot logs which are nicely formated for us to browse:

<figure><img src="../../.gitbook/assets/image (20).png" alt=""><figcaption><p>Robot Logs</p></figcaption></figure>

Congrats on running your first codebundle!

{% hint style="info" %}
If you don't want to use VSCode or Codespaces, your new repo has a built image that you can develop in!
{% endhint %}

```
docker run -d -p 3000:3000 --name mycodecollection ghcr.io/<your_name>/<repo>:latest
```

