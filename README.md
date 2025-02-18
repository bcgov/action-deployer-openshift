<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov/action-deployer-openshift)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov/action-deployer-openshift)](/../../pulls)
[![Apache 2.0 License](https://img.shields.io/github/license/bcgov/action-deployer-openshift.svg)](/LICENSE)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

<!-- Reference-Style link -->
[issues]: https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue
[pull requests]: https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/working-with-your-remote-repository-on-github-or-github-enterprise/creating-an-issue-or-pull-request

# OpenShift Deployer with Route Verification

GitHub Action. Deploy to OpenShift using templates. Runs route verification.  Most of the heavy lifting here is done in template configuration.

Testing has only been done with public containers on ghcr.io (GitHub Container Registry) so far.

# Usage

```yaml
- uses: bcgov/action-deployer-openshift@main
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
    
    # Overwrite objects using `oc apply` or only create with `oc create`
    # Expected errors from `oc create` are handled with `set +o pipefail`
    overwrite: "true"


    ### Typical / recommended
    
    # Template parameters/variables to pass
    parameters: -p ZONE=${{ github.event.number }}

    # Run a command after OpenShift deployment and any verifications
    # Useful for cronjobs and migrations
    post_rollout: oc create job "thing-$(date +%s)" --from=cronjob/thing

    # Timeout seconds, only affects the OpenShift deployment (apply/create)
    # Default = "15m"
    timeout: "15m"

    # Bash array to diff for build triggering
    # Optional, defaults to nothing, which forces a build
    triggers: ('frontend/')
    
    # Sets the health path to be used during deployment verification, does not require the '/' at the begining
    # Builds a health verification URL, form: <route_via_template>/<verifidation_path>
    verification_path: ""

    # Number of times to attempt deployment verification
    verification_retry_attempts: "3"

    # Seconds to wait between deployment verification attempts
    verification_retry_seconds: "10"


    ### Usually a bad idea / not recommended

    # Delete completed deployer and job pods?
    # Defaults to true
    delete_completed: true

    # Overrides the default branch to diff against
    # Defaults to the default branch, usually `main`
    diff_branch: ${{ github.event.repository.default_branch }}

    # Override default OpenShift CLI (oc) version; e.g. 4.13
    oc_version: "4.13"

    # Repository to clone and process
    # Useful for consuming other repos, defaults to the current one
    repository: ${{ github.repository }}

    ### Deprecated / will fail and provide directions

    # All penetration tests have been deprecated in favour of scheduled jobs or even workflow_dispatch
    # Please see https://github.com/zaproxy/action-full-scan for the source of the upstream action
    penetration_test:
    penetration_test_artifact:
    penetration_test_create_issue:
    penetration_test_fail:
    penetration_test_issue:
    penetration_test_token:
```

# Example, Single Template

Deploy a single template.  Multiple GitHub secrets are used.

```yaml
deploys:
  name: Deploys
  runs-on: ubuntu-24.04
  steps:
    - name: Deploys
      uses: bcgov/action-deployer-openshift.yml@main
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
    uses: bcgov/action-deployer-openshift.yml@main
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

# Example, Matrix / Post Rollout

Deploy and run a command (post hook).  Matrix values reference `post_rollout`, `overwrite` and `triggers`, despite not being present for all deployments.  This is acceptable, but unintuitive behaviour.

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
        post_rollout: oc create job "backend-$(date +%s)" --from=cronjob/backend
        triggers: ('backend/', 'frontend/')
steps:
  - name: Deploys
    uses: bcgov/action-deployer-openshift.yml@main
    with:
      name: ${{ matrix.name }}
      file: ${{ matrix.file }}
      oc_namespace: ${{ vars.OC_NAMESPACE }}
      oc_server: ${{ vars.OC_SERVER }}
      oc_token: ${{ secrets.OC_TOKEN }}
      overwrite: ${{ matrix.overwrite }}
      parameters: ${{ matrix.parameters }}
      post_rollout: ${{ matrix.post_rollout }}
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
      uses: bcgov/action-deployer-openshift.yml@main
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
        verification_url: health
```

# Output

The action will return a boolean (true|false) of whether a deployment has been triggered.  It can be useful for follow-up tasks, like verifying job success.

```yaml
- id: meaningful_id_name
  uses: bcgov/action-deployer-openshift@vX.Y.Z
  ...

- needs: [id]
  run: |
    echo "Triggered = ${{ steps.meaningful_id_name.outputs.triggered }}
```

# Route Verification

Deployment templates are parsed for a route.  If found, those routes are verified with a curl command for status code 200 (success).  This ensures that applications are accessible from outside their OpenShift namespace/project.

# Troubleshooting

## Dependabot Pull Requests Failing

Pull requests created by Dependabot require their own secrets.  See `GitHub Repo > Settings > Secrets > Dependabot`.

# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesty of the Forestry Digital Services, part of the Government of British Columbia. -->
