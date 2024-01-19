<!-- Badges -->
[![Issues](https://img.shields.io/github/issues/bcgov-nr/action-deployer-openshift)](/../../issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/bcgov-nr/action-deployer-openshift)](/../../pulls)
[![Apache 2.0 License](https://img.shields.io/github/license/bcgov-nr/action-deployer-openshift.svg)](/LICENSE)
[![Lifecycle](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

<!-- Reference-Style link -->
[issues]: https://docs.github.com/en/issues/tracking-your-work-with-issues/creating-an-issue
[pull requests]: https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/working-with-your-remote-repository-on-github-or-github-enterprise/creating-an-issue-or-pull-request

# OpenShift Deployer with Route Verification or Penetration Testing

GitHub Action. Deploy to OpenShift using templates. Runs route verification or penetration tests.  Most of the heavy lifting here is done in template configuration.

Testing has only been done with public containers on ghcr.io (GitHub Container Registry) so far.

# Usage

```yaml
- uses: bcgov-nr/action-deployer-openshift@main
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

    # Name for any penetration test issues or artifacts
    name: "frontend"

    # Template parameters/variables to pass
    parameters: -p ZONE=${{ github.event.number }}

    # Run a ZAProxy penetration test against any routes? [true/false]
    # Requires `name` to be set if enabled/true
    penetration_test: false

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

    # Repository to clone and process
    # Useful for consuming other repos, defaults to the current one
    repository: ${{ github.repository }}

    # Create an issue for penetration test results? [true|false]
    # Default = "true"
    penetration_test_create_issue: "true"

    # Allow ZAProxy alerts to fail the workflow? [true/false]
    # Warning: annoying!
    penetration_test_fail: false

    # Specify GITHUB_TOKEN or Personal Access Token (PAT) for issue writing
    # Defaults to inheriting from the calling workflow
    penetration_test_token: ${{ github.token }}


    ### Deprecated / will fail and provide directions

    # Replaced by `name` param
    penetration_test_artifact: frontend

    # # Replaced by `name` param
    penetration_test_issue: frontend
```

# Example, Single Template

Deploy a single template.  Multiple GitHub secrets are used.

```yaml
deploys:
  name: Deploys
  runs-on: ubuntu-latest
  steps:
    - name: Deploys
      uses: bcgov-nr/action-deployer-openshift.yml@main
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

Deploy multiple templates in parallel.  This time penetration tests are enabled and issues created.  Runs on pull requests (PRs).

```yaml
deploys:
name: Deploys
runs-on: ubuntu-latest
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
    uses: bcgov-nr/action-deployer-openshift.yml@main
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
      penetration_test: true
      triggers: ${{ matrix.triggers }}
```

# Example, Matrix / Post Rollout Hook

Deploy and run a command (post hook).  Matrix values refernce `post_rollout`, `overwrite` and `triggers`, despite not being present for all deployments.  This is acceptable, but unintuitive behaviour.

```yaml
deploys:
name: Deploys
runs-on: ubuntu-latest
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
    uses: bcgov-nr/action-deployer-openshift.yml@main
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
  runs-on: ubuntu-latest
  steps:
    - name: Deploys
      uses: bcgov-nr/action-deployer-openshift.yml@main
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

# Route Verification vs Penetration Testing

Deployment templates are parsed for a route.  If found, those routes are verified with a curl command for status code 200 (success).  This ensures that applications are accessible from outside their OpenShift namespace/project.

Provide `penetration_test: true` to instead run a penetration test using [OWASP ZAP (Zed Attack Proxy)](https://github.com/zaproxy/action-full-scan) against that route. `penetration_test_fail: false` can be used to fail pipelines where problems are found.  `penetration_test_issue: name` creates or comments on issues and is generally preferable over failing pipelines.

# Troubleshooting

## Dependabot Pull Requests Failing

Pull requests created by Dependabot require their own secrets.  See `GitHub Repo > Settings > Secrets > Dependabot`.

# Feedback

Please contribute your ideas!  [Issues] and [pull requests] are appreciated.

<!-- # Acknowledgements

This Action is provided courtesty of the Forestry Digital Services, part of the Government of British Columbia. -->
