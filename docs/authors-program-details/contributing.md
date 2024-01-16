# Contributing

There are many different ways to contribute to our community which are outlined below. You may also choose to have your work be private to you/your team. Here is an overview of the steps you'll be taking as you work through our author documentation:

1. Set up a local development environment and get a 'hello world' CodeCollection up and running on your machine. At this point, you can begin exploring the various Robot/Python libraries we've built or start building your own. [See these docs](https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle)
2. Work with a member of the RunWhen team (over slack) to get it published on the platform so it is built in to images and indexed by RunWhen's search. At this point, your SLIs and TaskSets can be used by anyone on the platform and your open source contributions can be showcased on the platform.
3. When ready, work with a member of the RunWhen team about moving your repo to the runwhen-contrib github organization, setting up a regression test environment (provided by RunWhen) and a support agreement. At this point, you start participating in the revenue share / royalties program.

More on the 2023 CodeCollection authors program is here:

<table><thead><tr><th width="401">Resources</th><th></th></tr></thead><tbody><tr><td>Technical documentation on starting your own CodeCollection</td><td><a href="https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle">These pages</a></td></tr><tr><td>Commercial documentation on the royalty / revenue share programs</td><td>The google doc <a href="https://docs.google.com/document/d/1oB1gEKvKhWQSyJ6AypeYOUpdqBTlGAE1Dflu7AECtyE/edit#heading=h.8w0xz5rsgbjo">here</a></td></tr><tr><td>Slack workspace to collaborate with RunWhen engineers and other CodeCollection Authors</td><td><p>Slack invite link <a href="https://join.slack.com/t/runwhen/shared_invite/zt-1l7t3tdzl-IzB8gXDsWtHkT8C5nufm2A">here</a>.</p><p><em>Feel free to introduce yourself on #general, and please join #codecollection-discussion and #codebundle-updates channels.</em></p></td></tr><tr><td>Community Discord Server where you can chat with the community and get help.</td><td>Discord invite link <a href="https://discord.gg/Ut7Ws4rm8Q">here</a>.</td></tr><tr><td>Talk with our founder</td><td>Book a time to talk <a href="https://cal.mixmax.com/kyle-runwhen/cc-author">here</a></td></tr></tbody></table>

## Development Process Overview

If you'd like to jump in see [these docs](https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle), but here's an overview of what development looks like

1. Set up your CodeCollection repository from the template provided to get started quickly.
2. Set up a local development environment using the RunWhen DevTools container and link it to the CodeCollection repository to get all of the same tools we use in development.
3. Iterate through local development, running your SLI or TaskSet on your local machine until the first CodeBundle is in reasonable shape. Commit it to your CodeCollection repo and create a tagged v0.0.1 release.
4. Work with a member of the RunWhen team to get your CodeCollection repository registered with the platform. This includes it in a platform CI/CD pipeline and makes it available for users to configure in their SLXs.
5. Build a test Workspace that shows off the initial capabilities of your CodeCollection. The RunWhen team can help make this available to all platform users, and help promote it.
6. Iterate for your next release.

## DevTools Container

Our DevTools Container is intended for use with VSCode running locally in a [VS Code / VS Code Server local container topology](https://code.visualstudio.com/docs/devcontainers/containers). While we encourage this approach, you can always run the image directly, described at the bottom of [this page](https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle).

## Coding Standards

While coding standards for Python are well documented, coding standards for Robot Framework are not as well understood. Docs for those are coming shortly.
