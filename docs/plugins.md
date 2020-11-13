## initialize
Determine if the plugin will participate in this deployment.
Plugins should return:
- `0` to be included.
- `86` to opt out.
- Any other status will be considered an error and abort the deployment.

## validate
## before-deploy
## undeploy
## deploy
## verify-deploy
## after-deploy
## finalize

initialize
validate
before-deploy
deploy-green
verify-green
switch-to-blue
undeploy-blue
after-deploy
finalize


initialize
validate
before-deploy
undeploy
deploy
verify-deploy
after-deploy
finalize






initialize
 0 - participate
 -1 - do not particpate
 * - failed to initialize


DOCKERHUB TO ECR

ECS
add logging config to docker-compose.yml

    logging:
      driver: awslogs
      options:
        awslogs-group: exemplar
        awslogs-region: us-gov-west-1
        awslogs-stream-prefix: exemplar


add to ecs-params.yml

task_definition:
  task_execution_role: $TASK_EXECUTION_ROLE
  ecs_network_mode: awsvpc


run_params:
  network_configuration:
    awsvpc_configuration:
      subnets:
        - "$SUBNET_1"
        - "$SUBNET_2"
      security_groups:
        - "$SECURITY_GROUP"
      assign_public_ip: ENABLED
