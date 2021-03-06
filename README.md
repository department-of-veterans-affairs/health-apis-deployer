# health-apis-deployer

## Contents
  + [Goals](#goals)
  + [Products](#products)
  + [Deployment Unit](#deployment-unit)
  + [Routes](#routes)
  + [K8S Membership](#k8s-membership)
  + [Environments](#environments)
  + [Sunsetting An Application](#sunsetting-an-application)

### Goals
- Enable products an easy to use, automated deployment mechanism into Health APIs Kubernetes
  environments independent of other products
- Enable blue/green style deployment
- Enforce best practices for portable smoke and regression testing
- Enable known safe rollback behaviors when deployments fail


### Products
The deployer becomes aware of applications via the _products_ folder. Each product contains a product.conf and product.yaml file.The .conf contains important product-specific information necessary for the deployer to install an application,
as well as optional configurations for customizing a product deployment. The .yaml contains kubernetes ingress rules for the given application. See the _exemplar.conf_ and _exemplar.yaml_ for an example product.


- Application's deployment unit artifact and current version
- Kubernetes Namespace assigned for the application
- Application's deployment unit decryption key
- Application Health Check path
- Load balancer rules with priority
- Kubernetes Ingress definitions
- *Automatic Deployment configuration

*Most products can be deployed to all known AWS Availability Zones in an environment. However, to control a product's deployment to specific AZs, override configuration is available.


### Deployment Unit
The _deployment unit_ (DU) is the deployment specification for a product. A DU is a self contained
_installer_ that is capable of deploying a specific version of a product in a given environment.
The DU is packaged with configurations necessary to run in each environment. For example, it has
configuration for QA, Lab, Production, etc. environments. See [Environments](#environments) below.


- Deployment Unit (DU) is a set of related k8s resources for a specific product
- Constrained to single namespace
- Includes deployment configurations, services, secrets, etc.
- Does not contain ingress objects or load balancer routes
- Jointly owned by the DevOps and product teams
- Maintained in a product specific GitHub repository
- Bundled as a tar.gz
- Potentially used in all environments at different time

[Read more](deployment-unit.md)


### Routes
A _route_ is a combination of application load balancer rules and k8s ingresses to provide
access to a service.

- Contains ingress objects for all products
- Contains load balancer routes for all products
- Owned by the DevOps team
- Product teams must request ingress objects and load balancers routes from the DevOps team
- Maintained in _this_ GitHub repository
- Bundled as a docker image

While products can be mostly managed independently of one another, the HTTP routes must be
managed together. Furthermore, routes have the potential to break access to other services if not
coordinated across all products. The DevOps team provides oversight to ensure that routes do not
conflict.

##### Scripts Used For Coordinating Routes:

- `list-load-balancer-rules`
  - Finds all load-balancer rules and ensures no rules overlap or violate the agreed upon method for determining priority
  - Script is run during deployer upgrades/deployments and will cause a failure
- `list-ingress-rules`
  - Finds all ingress rules, determines priority, and ensures all given routes map to the correct ingress rule (based on application)
  - Relys on the test paths within the `ingress.tests` file located in the `health-apis-deployer` root directory
  - Script is run during deployer upgrades/deployments and will cause a failure

[Read more](ingress-and-load-balancer-rules.md)

### K8S Membership
Moving applications to the Health APIs k8s cluster is coordinated responsibility between product
teams and DevOps team.

1. Contact the DevOps team to request access
2. DevOps team will negotiate a namespace name that is assigned to your product
3. DevOps team will negotiate routes needed by your product
4. DevOps team will implement routes and apply changes to k8s
5. Product team will create DU deployer and create a PR
6. DevOps team or designated approvers will approve DU configuration and merge
7. Jenkins will execute DU deployer to apply changes

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
- `QA` > `Lab QA` > `Lab`

The Jenkins orchestration pipeline will manage progression of deployment units through the
different environments. Deployment unit packages are versioned and managed in Dockerhub. The
pipeline will promote a specific version along the path outlined above. At any given time,
different versions of a DU may be deployed in different environments, e.g. version `1.5.1-f4d4274`
may be deployed to QA, but version `1.4.7-3f461a0` is deployed to production. If testing is
successful, `1.5.1-f4d4274` will be promoted to higher environments over time.
_Promotion process is not fully designed but will involve version manual interactions to promote
applications, at least in the initial phase_

### Sunsetting An Application
When an application is no longer in use, it may be removed from the platform. The process for removal of an application is as follows:

1. [`health-apis-promotatron`](https://github.com/department-of-veterans-affairs/health-apis-promotatron)
    + Move promotion scripts to the `/attic` directory
    + Remove the scripts from the `promoters` map in the Jenkinsfile
2. Platform
    + If any health checks exist at the platform level (pingdom, statuspage, etc.) they must be removed _first_ before any other action is taken to remove an application
    + Remove the load-balancer rules in AWS so that traffic is no longer being routed to the application
    + Remove the applications namespace from all environments it has been deployed to in Kubernetes
3. [`health-apis-deployer`](https://github.com/department-of-veterans-affairs/health-apis-deployer)
    + Move the applications `.yaml` and `.conf` files from the `/products` directory to `/attic`
    + Remove the product's test endpoints from `ingress.tests`
    + Remove the application from the `products` map in the Jenkinsfile
4. Application Repostiories 
    + Archive the product's GitHub repository (or repositories)
    + Archive the product's deployment-unit GitHub repository
