# Requirements

## Concepts / Resources

Familiarity with:&#x20;

* Our [contributing doc](../cc-dev/contributing.md)
* RunWhen [Terms and Concepts](https://docs.runwhen.com/public/runwhen-platform/terms-and-concepts)
* Review our [code-of-conduct.md](../authors-program-details/code-of-conduct.md "mention")
* Google [python style guide](https://google.github.io/styleguide/pyguide.html); we generally try to follow it but do stray when needed for certain designs.
* [Robot Framework](https://robotframework.org/robotframework/latest/RobotFrameworkUserGuide.html), although a strong understanding of Robot is not needed. We try to handle complex logic at the python or external script level and use Robot like a configuration language, passing data and settings between Robot Tasks.



## Development Environment

Authoring and testing CodeBundles requires:&#x20;

* A Public [GitHub](https://www.github.com) Repository
* The ability to run a devcontainer image (e.g. via [GitHub Codepaces](https://github.com/features/codespaces), [VSCode](https://code.visualstudio.com/docs/devcontainers/containers), [GitPod](https://www.gitpod.io/) etc.)
* Lab / test infrastructure; CodeBundles should be adequately tested against test infrastructure from the local environment prior to uploading to the RunWhen Platform Workspace for testing.
* A [RunWhen Platform Workspace](https://docs.runwhen.com/public/getting-started/creating-a-runwhen-workspace); for thorough testing, the RunWhen Platform (SaaS) service should be able to access the test infrastructure.&#x20;



## CodeCollection Repository Setup

To get started, first create a CodeCollection for your first CodeBundle it reside in. Using the repository [template ](https://github.com/runwhen-contrib/codecollection-template)on GitHub, select the `Create a new repository` option from the `Use this template` dropdown.



## CodeCollection Development Image

The CodeColleciton development image is pulled in through the devcontainer.json spec and is built from the local Dockerfile inside of the CodeColellection template image. Developers can customize this Dockerfile as needed, though it can't guartee that tools installed in this image will function properly within the SaaS platform and a conversation with our team on Slack may be required.&#x20;

<figure><img src="../.gitbook/assets/codecollection-development-image-layersdrawio.svg" alt=""><figcaption><p>CodeCollection Development Image Layers</p></figcaption></figure>



