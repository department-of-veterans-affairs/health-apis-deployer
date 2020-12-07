# health-apis-deployer (d2)

## Contents
- [Goals](#goals)
- [Overview](#overview)
- [Products](#products)
- [Deployment Unit](#deployment-unit)
- [Routes](#routes)
 [Environments](#environments)

### Goals
- Enable products an easy to use, standard, automated deployment mechanism into AWS
- Enable blue/green style deployment
- Enforce best practices for portable smoke and regression testing
- Enable known safe rollback behaviors when deployments fail

### Overview
The Deployer works as a set plugins operating in defined [lifecycles](docs/lifecycles.md) to deploy your application in a controlled, repeatable, and predictable way. As an application owner, you create a [deployment unit](docs/deployment-unit.md) that specifies what you want and the Deployer machinery takes care of details, such as creating target groups or ALB rules based on a minimal specification.

The Deployer is not a general purpose solution for provisioning AWS resources. It is an opinionated tool that will consistently and reliably deploy specific AWS assets to work with the DVP environment.

Through the [deployment unit](docs/deployment-unit.md), you can specify what deployment features you want from the following plugins
- [ECS](docs/ecs.md) tasks and services for application deployment
- [Callculon Timers](docs/timer.md) for web-based timers
- [Integration Testing](docs/it.md)
- [S3](docs/s3.md) for deployment specific files

### Products
A _product_ is a set components, e.g. applications or timers, that are deployed to an environment.
The deployer becomes aware of products via the [products](https://github.com/department-of-veterans-affairs/health-apis-deployer/tree/qa/products) folder on the `qa` branch. The DevOps team maintains product registration.

Each product contains a `product.conf`. This file contains important product-specific information necessary for the deployer to install an application.

```
DU_ARTIFACT ................... The maven artifact ID of the deployment unit.
DU_VERSION .................... The maven version numnber of the deployment unit artifact
DU_DECRYPTION_KEY ............. The secret key name used to decrypt the deployment unit secrets

# If using ECS
DU_HEALTH_CHECK_PATH .......... The health path only that will be used to monitor the service target group
DU_ECS_EXPOSE_SERVICE ......... Which ECS service to expose on the application load balancer (ALB)
DU_LOAD_BALANCER_RULES[###] ... One or more ALB paths to route to your application
                                The path must be agreed upon by the DevOps and application owner
                                The ALB slot number is determined by the DevOps team 
```


### Deployment Unit
The _deployment unit_ (DU) is the deployment specification for a product. A DU is a self contained
_installer_ that is capable of deploying a specific version of a product in a given environment.
The DU is packaged with configurations necessary to run in each environment. For example, it has
configuration for QA, Lab, Production, etc. environments. See [Environments](#environments) below.

A Deployment Unit (DU) is
- configuration for a specific product
- a bundle of deployment configurations, services, secrets, etc. for all environments
- bundled as a tar.gz and stored in the DVP Nexus artifact repository
- potentially used in all environments at different times
- not configuration for load balancer routes
- owned by the product teams
- maintained in a product specific GitHub repository

[Read more](docs/deployment-unit.md)


### Routes
A _route_ is a application load balancer rule that provides access to service.

Routes are
- paths on the ALB used to access exposed services
- mutally agreed upon by the DevOps and product teams, but owned by the DevOps team
- maintained in _this_ GitHub repository

While products can be mostly managed independently of one another, the HTTP routes must be
managed together. Furthermore, routes have the potential to break access to other services if not
coordinated across all products. The DevOps team provides oversight to ensure that routes do not
conflict.


### Environments
- QA
- UAT
- Staging
- Production
- Staging-Lab
- Lab

Path through environments
- `QA` > `UAT` > `Staging` > `Production` (When user testing is required)
- `QA` > `Staging` > `Production`
- `QA` > `Staging Lab` > `Lab`

The Jenkins orchestration pipeline will manage progression of deployment units through the
different environments. Deployment unit packages are versioned and managed in Nexus. The
pipeline will promote a specific version along the path outlined above. At any given time,
different versions of a DU may be deployed in different environments, e.g. version `1.5.1`
may be deployed to QA, but version `1.4.7` is deployed to production. If testing is
successful, `1.5.1` will be promoted to higher environments over time.
