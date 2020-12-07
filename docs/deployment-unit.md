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
This file can be empty.
See [IT](it.md) for details.

> **WARNING**: Docker env files are literal and do not use shell evaluation. Quotes, dollar signs,
new lines, etc. will be passed literally to your application.

`test.conf`  
Test container configuration for regression and smoke tests.
See [IT](it.md) for details.

`timer-*.json`  
Optional [Callculon](https://github.com/department-of-veterans-affairs/lighthouse-callculon)
timers. You may specify as many as you need. Timer configuration will be processed for substitution
and will be augmented with environment, product, version, and deployment ID information.
See [Timers](timers.md) for details.

`ecs/docker-compose.yml`  
ECS CLI compatible Docker compose template. This file we be processed as described below.
See [ECS](ecs.md) for details.

`ecs/ecs-params.yml`  
ECS CLI compatible parameter template. This file we be processed as described below.
See [ECS](ecs.md) for details.

`s3`  
This directory will be used to populate a deployment-specific S3 bucket.
See [S3](s3.md) for details.

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

