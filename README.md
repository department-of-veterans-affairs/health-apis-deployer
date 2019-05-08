# health-apis-deployer


### Goals
- Enable products an easy to use, automated deployment mechanism into Health APIs Kubernetes 
  environments independent of other products
- Enable blue/green style deployment
- Enforce best practices for portable smoke and regression testing
- Enable known safe rollback behaviors when deployments fail


### Deployment Unit
The _deployment unit_ is the deployment specification for a product.

- Deployment Unit (DU) is a set of related k8s resources for a specific product
- Constrained to single namespace
- Includes deployment configurations, services, secrets, etc.
- Does not contain ingress objects or load balancer routes
- Jointly owned by the DevOps and product teams
- Maintained in a product specific GitHub repository
- Bundled as a docker image

[Read more](deployment-unit.md)


### Routes
A _route_ is a combination of application load balancer rules and k8s ingresses to provide
access to a service.

- Contains ingress objects for all products
- Contains load balancer routes for all products
- Owned by the DevOps team
- Product teams must request ingress objects and load balancers routes from the DevOps team
- Maintained in a _this_ GitHub repository
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
