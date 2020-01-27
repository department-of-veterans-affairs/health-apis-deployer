# health-apis-deployer

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

*Most products can be deployed to all known AWS Availability Zones in an environemt. However, to control a product's deployment to specific AZs, overide configuration is available. 


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

### K8S membership
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
