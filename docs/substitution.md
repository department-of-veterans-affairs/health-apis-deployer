# Substitution for configuration files
Certain files as determined by each plugin are eligible for deploy-time substution. Eligible files will be processed using `envsubst` to provide environment specific values to be injected into the yaml.
Exported environment variables from `deployment.conf` and the environment specific conf,
e.g., `qa.conf` will be set. Additionally, the following variables will be also be set.

```
ENVIRONMENT ................... The environment, e.g., qa or staging-lab
DEPLOYMENT_ID ................. A complete unique ID for the deployment, 
                                e.g., production-360-8dd3e07-claims-attributes
SHORT_DEPLOYMENT_ID ........... A short, but unique ID for the deployment
BUILD_TIMESTAMP ............... Build start time in `date` format,
                                e.g. Thu Nov 12 14:50:15 EST 2020
BLUE_LOAD_BALANCER_PROTOCOL ... The protocol to use when accessing your service:
                                e.g., https or http
BLUE_LOAD_BALANCER ............ Hostname of the ALB
BLUE_LOAD_BALANCER_PORT ....... The port on the ALB 
                                e.g., 443
DEPLOYMENT_AWS_S3_BUCKET ...... The name of the S3 bucket made available to the
                                application.
DEPLOYMENT_AWS_S3_FOLDER ...... The name of the folder in the S3 bucket specifically
                                for this application.
```

### Gotchas
Files with `$` that naturally occur can be mistaken by `envsubst` for substitions. You may need to define a substition to avoid erroneous behavior. 