---
description: >-
  This page assumes you've created a repo from the template:
  https://github.com/runwhen-contrib/codecollection-template
---

# Scan For Crashing Pods

In this example we'll look at taking a more "ops" approach and implement a pod healthcheck in Bash, and then wrap it in the Robot Keyword to demonstrate how you can wrap your pre-existing Bash scripts.

* First We'll write the bash that fetches the pods from a given namespace, and tells us if any are crashlooping:

<figure><img src="../.gitbook/assets/image (2) (1).png" alt=""><figcaption><p>Pod debug script</p></figcaption></figure>

Then we simply call this bash script from Robot using ther `Run Process` Keyword:

<figure><img src="../.gitbook/assets/image (3) (1).png" alt=""><figcaption></figcaption></figure>



And the output we get when running it using `ro` : &#x20;

<figure><img src="../.gitbook/assets/image (4).png" alt=""><figcaption><p>Pod Health Check Output</p></figcaption></figure>

Now you know how to take all your bash files you've had hidden away and run them in Robot for use in the codecollection - sharing is caring!

Source: [https://github.com/runwhen-contrib/codecollection-template/tree/demo/codebundles/pod-healthcheck](https://github.com/runwhen-contrib/codecollection-template/tree/demo/codebundles/pod-healthcheck)
