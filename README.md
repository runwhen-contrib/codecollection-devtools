<p align="center">
  <a href="https://runwhen.slack.com/join/shared_invite/zt-1l7t3tdzl-IzB8gXDsWtHkT8C5nufm2A">
    <img src="https://img.shields.io/badge/Join%20Slack-%23E01563.svg?&style=for-the-badge&logo=slack&logoColor=white" alt="Join Slack">
  </a>
</p>

# RunWhen CodeCollection Devtools

[![Tests](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/smoke-test.yaml/badge.svg)](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/smoke-test.yaml)

[![Build](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/build-push.yaml/badge.svg)](https://github.com/runwhen-contrib/codecollection-devtools/actions/workflows/build-push.yaml)

This repository is for managing developer tooling related to creating your own CodeCollections. You can use it to do development directly from source, in a devcontainer from source, or from the image. CodeCollections can also use this image as a base for their dev images. Check the [docs](https://docs.runwhen.com/public/v/runwhen-authors/) for more information.

Looking to be a contributor for CodeCollections or start your own? We'd love to collaborate! Head on over to our [technical docs](https://docs.runwhen.com/public/v/runwhen-authors/codecollection-development/getting-started/running-your-first-codebundle) to get started.

## Getting Started
File Structure overview of devcontainer when launched from a CodeCollection:
```
-/app/
    |- auth/ # store secrets here, it should already be properly gitignored for you
    |- codecollection/
    |   |- codebundles/ # stores codebundles that can be run during development
    |   |- libraries/ # stores python keyword libraries used by codebundles
    |- dev_facade/ # provides interfaces equivalent to those used on the platform, but just dry runs the keywords to assist with development
    ...
```

The included script `ro` wraps the `robot` RobotFramework binary, and includes some extra functionality to write files to a consistent location for viewing in a HTTP server at http://localhost:3000/ that is always running as part of the devcontainer.

### Quickstart

Navigate to the codebundle directory
`cd codecollection/codebundles/hello_world/`

Run the codebundle
`ro sli.robot`
