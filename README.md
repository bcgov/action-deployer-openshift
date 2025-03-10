<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov/action-deployer-openshift)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov/action-deployer-openshift)](/../../pulls)
[![Apache 2.0 License](https://img.shields.io/github/license/bcgov/action-deployer-openshift.svg)](/LICENSE)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

<!-- Reference-Style link -->
[issues]: https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue
[pull requests]: https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/working-with-your-remote-repository-on-github-or-github-enterprise/creating-an-issue-or-pull-request

# OpenShift Deployer

Deploy to OpenShift using templates.  This action is a wrapper around the OpenShift CLI (oc) and is intended to be used with OpenShift 4.x.

Testing has only been done with public images (ghcr.io, hub.docker.com) so far.

# Usage

```yaml
- uses: bcgov/action-deployer-openshift@X.Y.Z
  with:
    ### Required

    # OpenShift template file
    file: frontend/openshift.deploy.yml

    # OpenShift project/namespace
    oc_namespace: abc123-dev

    # OpenShift server
    oc_server: https://api.silver.devops.gov.bc.ca:6443
    
    # OpenShift token
    # Usually available as a secret in your project/namespace
    oc_token: ${{ secrets.OC_TOKEN }}


    ### Typical / recommended
    
    # Overwrite objects using `oc apply` or only create with `oc create`
    # Expected errors from `oc create` are handled with `set +o pipefail`
    overwrite: "true"

    # Template parameters/variables to pass
    parameters: -p ZONE=${{ github.event.number }}

    # Timeout seconds, only affects the OpenShift deployment (apply/create)
    # Default = "15m"
    timeout: "15m"

    # Bash array to diff for build triggering
    # Optional, defaults to nothing, which forces a build
    triggers: ('frontend/')


    ### Usually a bad idea / not recommended

    # Overrides the default branch to diff against
    # Defaults to the default branch, usually `main`
    diff_branch: ${{ github.event.repository.default_branch }}

    # Override default OpenShift CLI (oc) version; e.g. 4.13
    oc_version: "4.13"

    # Repository to clone and process
    # Useful for consuming other repos, defaults to the current one
    repository: ${{ github.repository }}
```

# Example, Single Template

Deploy a single template.  Multiple GitHub secrets are used.

```yaml
deploys:
  name: Deploys
  runs-on: ubuntu-24.04
  steps:
    - name: Deploys
      uses: bcgov/action-deployer-openshift.yml@X.Y.Z
      with:
        file: frontend/openshift.deploy.yml
        oc_namespace: ${{ vars.OC_NAMESPACE }}
        oc_server: ${{ vars.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
        overwrite: true
        parameters:
          -p MIN_REPLICAS=1 -p MAX_REPLICAS=2
          -p PR_NUMBER=${{ github.event.number }}
        triggers: ('frontend/')
```

# Example, Matrix / Multiple Templates

Deploy multiple templates in parallel.  Runs on pull requests (PRs).

```yaml
deploys:
name: Deploys
runs-on: ubuntu-24.04
  strategy:
    matrix:
    name: [backend, database, frontend, init]
    include:
      - name: backend
        file: backend/openshift.deploy.yml
        overwrite: true
        parameters: -p MIN_REPLICAS=1 -p MAX_REPLICAS=2
        triggers: ('backend/')
      - name: database
        overwrite: false
        file: database/openshift.deploy.yml
      - name: frontend
        overwrite: true
        file: frontend/openshift.deploy.yml
        parameters: -p MIN_REPLICAS=1 -p MAX_REPLICAS=2
        triggers: ('backend/', 'frontend/')
      - name: init
        overwrite: false
        file: common/openshift.init.yml
steps:
  - name: Deploys
    uses: bcgov/action-deployer-openshift.yml@X.Y.Z
    with:
      name: ${{ matrix.name }}
      file: ${{ matrix.file }}
      oc_namespace: ${{ vars.OC_NAMESPACE }}
      oc_server: ${{ vars.OC_SERVER }}
      oc_token: ${{ secrets.OC_TOKEN }}
      overwrite: ${{ matrix.overwrite }}
      parameters:
        -p COMMON_TEMPLATE_VAR=whatever-${{ github.event.number }}
        ${{ matrix.parameters }}
      triggers: ${{ matrix.triggers }}
```

# Example, Matrix

Deploy an OpenShift template.  When values (e.g. overwrite, triggers) are not provided defaults will be used.  This is convenient, but unintuitive.

```yaml
deploys:
name: Deploys
runs-on: ubuntu-24.04
  strategy:
    matrix:
    name: [database, frontend]
    include:
      - name: database
        overwrite: false
        file: database/openshift.deploy.yml
      - name: frontend
        file: frontend/openshift.deploy.yml
        parameters: -p MIN_REPLICAS=1 -p MAX_REPLICAS=2
        triggers: ('backend/', 'frontend/')
steps:
  - name: Deploys
    uses: bcgov/action-deployer-openshift.yml@X.Y.Z
    with:
      name: ${{ matrix.name }}
      file: ${{ matrix.file }}
      oc_namespace: ${{ vars.OC_NAMESPACE }}
      oc_server: ${{ vars.OC_SERVER }}
      oc_token: ${{ secrets.OC_TOKEN }}
      overwrite: ${{ matrix.overwrite }}
      parameters: ${{ matrix.parameters }}
      triggers: ${{ matrix.triggers }}
```

# Example, Using a different endpoint for deployment check

Deploy a template and set the after deployment check to hit the **/health** endpoint.  Multiple GitHub secrets are used.

```yaml
deploys:
  name: Deploys
  runs-on: ubuntu-24.04
  steps:
    - name: Deploys
      uses: bcgov/action-deployer-openshift.yml@X.Y.Z
      with:
        file: backend/openshift.deploy.yml
        oc_namespace: ${{ vars.OC_NAMESPACE }}
        oc_server: ${{ vars.OC_SERVER }}
        oc_token: ${{ secrets.OC_TOKEN }}
        overwrite: true
        parameters:
          -p MIN_REPLICAS=1 -p MAX_REPLICAS=2
          -p PR_NUMBER=${{ github.event.number }}
        triggers: ${{ matrix.triggers }}
```

# Lite Mode for Pull Requests

Pull request (PR) deployments will automatically use lite mode.  This is ideal for resource-limited environments.

Object types removed:
- HorizontalPodAutoscaler
- PodDisruptionBudget

Deployment modifications:
- Replicas limited to 1 (deployment.spec.replicas)
- Rollout strategy limited to `Recreate` (deployment.spec.strategy.type)

# Output

The action will return a boolean (true|false) of whether a deployment has been triggered.  It can be useful for follow-up tasks, like running tests.

```yaml
- id: meaningful_id_name
  uses: bcgov/action-deployer-openshift@vX.Y.Z
  ...

- needs: [id]
  run: |
    echo "Triggered = ${{ steps.meaningful_id_name.outputs.triggered }}"
```

# Deprecations

## Deployment Configs

The DeploymentConfig API has been [deprecated by Red Hat](https://access.redhat.com/articles/7041372).  If this action is used to deploy a template containing DeploymentConfig objects, it will provide an error message and exit.

## Parameters

The parameters `delete_completed` and `post_rollout` are deprecated.  This functionality is better served by our [bcgov/action-oc-runner](https://github.com/bcgov/action-oc-runner) action.

The parameters `verification_path`, `verification_retry_attempts` and `verification_retry_seconds` are deprecated.  Please use OpenShift [health checks](https://docs.openshift.com/container-platform/4.18/applications/application-health.html) instead.

# Troubleshooting

## Dependabot Pull Requests Failing

Pull requests created by Dependabot require their own secrets.  See `GitHub Repo > Settings > Secrets > Dependabot`.

# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesy of the Forestry Digital Services, part of the Government of British Columbia. -->
