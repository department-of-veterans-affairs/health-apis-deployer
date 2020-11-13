# ecs

Add ECS services and tasks to your deployment.

## Activation
Requires files
- `ecs/docker-compose.yml`
- `ecs/ecs-params.yml`

## Substitution
The following files are eligible for [substitution](substitution.md).
- `ecs/docker-compose.yml`
- `ecs/ecs-params.yml`

## Configuration
### `docker-compose.yml`
Example
```
version: '3'
services:
  exemplar:
    image: vasdvp/health-apis-exemplar:$EXEMPLAR_VERSION
    ports:
      - "8080:8080"
    environment:
      SOME_OPTION: $SOME_VALUE
      SOME_OPTION: some_value
```

This is a simplified AWS ECS compatible docker compose file.
- You may define one or more services, however, only one service can be exposed on the ALB. The exposed service is defined in the product configuration maintained by DevOps.
- Exposed service must have a port mapping.
- Docker image may be either from Dockerhub, e.g. `vasdvp` organziation or a DVP ECR repository, e.g. `1234567890.dkr.ecr.us-gov-west-1.amazonaws.com`. Images in Dockerhub will be moved to ECR automatically.
- Cloudwatch logging will automatically be configured for you with a log group per environment per service, e.g., `production-exemplar`. Any logging configuration defined here will be discarded. Specifically, `.services.${service}.logging` will be re-written.
- Environment variables may be specified as constants or deploy time substitutions. This should not contain any secrets. Use `ecs-params.yml` for sensitive information.

### `ecs-params.yml`
Example
```
version: 1
task_definition:
  task_size:
    cpu_limit: 1024
    mem_limit: 2GB
  services:
    exemplar:
      secrets:
      - name: SOME_SECRET
        value_from: /dvp/qa/exemplar/very-secret
      cpu_shares: 1024
      mem_limit: 2GB
      healthcheck:
        test: [ "CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1" ]
        interval: 5
        timeout: 2
        retries: 3
        start_period: 45s
```
This simplified ECS parameters is used to set resource limits, health checks, and pass secrets. 
- Secrets are stored in AWS Parameter Store. If you have sensitive data, work with the DevOps team to add them to Parameter Strre.
- Health checks are essential for good fail over behavior, your application should define a health that will be used to determine if the application is running or not.
- Networking and security settings will be automatically configured based on the environment. Specifically, `.task_definition.services.${service}.ecs_network_mode`, `.task_definition.services.${service}.task_execution_role`, and `.run_params` will be re-written.

## Lifecycles
- `initialize`
  - Verifies service defined by `DU_ECS_EXPOSE_SERVICE` is present and has a port mapping
  - Imports Docker images to ECR from Dockerhub if necessary
  - Updates `docker-compose.yml` and `ecs-params.yml`
- `deploy-green`
  - Creates a new target group
  - Adds or replaces rules on the green ALB for this product
  - Deploys the service and waits for it to become healthy
- `switch-to-blue`
  - Removes rules from the green ALB for this product
  - Adds rules on the blue ALB for this product
  - Deprioritizes old rules on the blue ALB for this product to allow the new rules to fire
- `after-verify-blue`
  - Removes the old rules from the blue ALB
  - Removes the old target group
  - Removes the old services
  - Removes the old task definitions

### Rollback Lifecycles
- `rollback`
  - Restores old rules to their previous priority if deprioritized
  - Removes new rules from blue ALB if present
  - Removes new rules from green ALB if present
  - Removes new target group if present
  - Removes new service if present
  - Removes new task definition if present