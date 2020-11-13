# Deployment Unit

## Contents
- [Product Repository Structure](#product-repository-structure)
  - [Conf files](#conf-files)
  - [Testvars files](#testvars-files)
  - [Substitution for Configuration Files](#substitution-for-configuration-files)
  - [S3 Buckets](#s3-buckets)
  - [Protecting Sensitive Information](#protecting-sensitive-information)
- [Blue/Green Deployment Process](#bluegreen-deployment-process)
- [Testing Deployment Units](#testing-deployment-units)
  - [Regression tests](#regression-tests)
  - [Smoke tests](#smoke-tests)
  - [Test container contract](#test-container-contract)

## Product Repository Structure
```
<product>/
├── Jenkinsfile
├── pom.xml
├── deployment.conf
├── ${environment}.conf
├── ${environment}.testvars
├── test.conf
├── timer-*.json
├─┬─ ecs/
│ ├── docker-compose.yml
│ └── ecs-params.yml
└─┬─ s3/
  ├── */*
  ├── */*.properties
  ├── */*.conf
  ├── */*.yml
  └── */*.yaml
```

`Jenkinsfile`  
Responsible for building DU container and deploying it to Nexus as a project assembly.

`deployment.conf`  
Configuration variables that will be applied in all environments, such as application versions.

`${environment}.conf`  
Configuration files for specific environments, e.g., `qa.conf`, `staging.conf`, or `production.conf`
You must have a configuration file for each environment you wish to deploy in. 
This file can be empty.

`${envionrment}.testvars`  
Environment variable files for specific environments used when running tests, e.g., `staging-lab.testvars`, `lab.testvars`
You must have a testvars file for each environment you wish to deploy in. 
This file can be empty.

> **WARNING**: Docker env files are literal and do not use shell evaluation. Quotes, dollar signs,
new lines, etc. will be passed literally to your application.

`test.conf`  
Test container configuration for regression and smoke tests. File contents must set `TEST_IMAGE`
to Docker image to run for tests, e.g.,
```
export TEST_IMAGE=chillo/armadillo:$ARMADILLO_VERSION
```

`timer-*.json`
Optional [Callculon](https://github.com/department-of-veterans-affairs/lighthouse-callculon)
timers. You may specify as many as you need. Timer configuration will be processed for substitution
and will be augmented with environment, product, version, and deployment ID information.
See [Timers](timers.md) for details.

`ecs/docker-compose.yml`  
ECS CLI compatible Docker compose template. This file we be processed as described below.

`ecs/ecs-params.yml`  
ECS CLI compatible parameter template. This file we be processed as described below.

`s3`
This directory will be used to populate a deployment-specific S3 bucket. The contents will processed
using the substitution rules used with conf files. This directory structure can be as deep as
need be. The following file types will be processed for substitution:
- `*.properties`
- `*.conf`
- `*.yaml` or `*.yml`

---

### Conf files
`.conf` files are bits of bash code that are evaluated during the deployment process. `.conf`
files may contain bits of logic, functions, etc. to compute values that will be used. However, to
enable substitution in other files, such as `docker-compose.yml`, variables must be exported, e.g.,
```
export CHILLO=ARMADILLO`   # $CHILLO is available for substitution
WIGGLY=PIGGLY              # $WIGGLY is not available
```

### Testvars files
`.testvars` contain variables needed for tests in in Docker `--env-file` format and will be
used to set environment variables during test execution. Format is `var=value`, one declaration per line, and treated literally, e.g.,
```
CHILLO=ARMADILLO
WIGGLY=PIGGLY
```
See the [it plugin](it.md) for more details.

### Substitution for configuration files
Certain files are eligible for deploy-time [substution](substitution.md). 


### Protecting Sensitive Information
`.conf`  and `.testvars` files may need to contain sensitive information such as access tokens or passwords. These files should be protected using the deployment unit toolkit.

Decryption key must be stored in as a Jenkins credential to be used to execute the DU docker image. Coordinate with the DevOps team if you need encryption.



---
# **TODO** REVISE DOCUMENTATION BELOW THIS LINE


## Blue/Green Deployment Process

The `health-apis-deployment-unit` docker image provides machinery necessary to deploy products into
the k8s cluster. Deployments are orchestrated at a higher level by Jenkins which kick off
deployment, trigger rollback if necessary, and handle reporting.

For a given environment
- Perform sanity check against `deployment.yaml`
- Load `deployment.conf`
- Load `${environment}.conf`
- Perform `envsubst` style substitution on the `deployment.yaml` and other files subject to
  substitution rules to produce a final configuration
- Remove any timers associated to product
- Deploy the product to each Availability Zone as described below
- Initialize any timers

For each Availability Zone supported by the cluster in this environment
- Detach the deployment unit's green target group from the k8s blue load balancer
- Remove all rules from green load balancer
- Save ingress rules from the DU namespace
- Delete the DU namespace
- Create the namespace
- Restore ingress rules
- Apply substituted final configuration
- Attach deployment unit's green target group to the k8s green load balancer
- Load `test.conf`
- Run regression test container against green load balancer

On regression test success
- Detach the deployment unit's green target group from the k8s green load balancer
- Attach the deployment unit's blue target group to the k8s blue load balancer
- Run smoke test container against blue load balancer
- Begin next AZ

On regression test or smoke test failure in QA
- Environment is left in current state and is available for debugging which may be a mixture of
  partially upgraded AZs
- Gather logs from pods
- Deployment to next AZ is skipped

On regression test or smoke test failure in upper environments
- Logs are captured from all pods in the failed AZ and provided on Jenkins
- Previously installed version is re-applied to this and any previously updated AZs by re-running
  previously installed versions docker image
- Blue load balancer is restored
- Run smoke test container against blue load balancer


Read more about [Blue/Green](blue-green.md)

> The above steps are achieved by a combination of the deployment unit docker image, the routes
docker image, and the Jenkins pipeline that orchestrates the pipeline.

> Regression and smoke test container stdout will be captured and made available on Jenkins.

---
## Testing Deployment Units
The Orchestrating Jenkins pipeline may choose to perform regression or smoke tests based on
various situations.

##### Regression tests
- Ran during product version install
- May be long running

##### Smoke tests
- Ran during route changes to verify connectivity to DU through load balancers and k8s ingress
- Should execute quickly
- Should exercise operations that cover each expect HTTP path
  For example, if the DU expects paths `/awesome/possum` and `/chillo/armadillo` to be available,
  then a smoke test might simply contain two reads and a health check.

##### Test container contract
- Test container will support test type arguments: `regression-test` and `smoke-test`
- Test container will accept one test type argument at a time: `regression-test` or `smoke-test`
- Test container will be provided the environment variables as listed below
- Test container shall provide an exit code of `0` to indicate success and any non-zero value
  to indicate failure
- Standard out will be captured and provided on Jenkins

The following environment variables will be provided to the test container in both regression and
smoke test modes. (Description above).
- `K8S_ENVIRONMENT`
- `K8S_DEPLOYMENT_ID`
- `K8S_LOAD_BALANCER`

Additionally, any values in `${environment}.testvars` will be passed to your container.

Example
```
docker run \
  --rm \
  --network host \
  --env-file qa.testvars \
  --env K8S_ENVIRONMENT=qa \
  --env K8S_DEPLOYMENT_ID=ABC123 \
  --env K8S_LOAD_BALANCER=green.qa.ligthouse.va.gov \
  vasdvp/health-apis-data-query-test \
  regression-test
```




### S3 Buckets

**WARNING** THIS FEATURE IS IN PROGRESS AND NOT CURRENTLY AVAILABLE

Environment-specific S3 buckets will be used to house deployment-specific folders.
The following environment variables will be provided for substitution in your files.

`DU_AWS_BUCKET_NAME`
The environment specific bucket name

`DU_S3_FOLDER`
The deployment specific folder. This folder will be populated with your deployment unit's `s3/`
folder contents and will be automatically deleted when a deployment is removed from kubernetes.
