# D2 Lifecylces
The Deployer operates as a set of plugins performing specific tasks at specific points of the deployment called _lifecycles_.


`activate`  
 Plugins decides if it will participate in the deployment based on the deployment unit. 

`priority`  
Plugins decide the relative order in each plugin will execute in the remaining phases.

`initialize`  
Initialize any plugin specific data or perform other tasks require for the plugin to operate. 

`validate`  
Perform validation of the deployment unit configuration.

`before-deploy-green`  
Perform any necessary processing just before attempting to deploy new AWS assets.

`deploy-green`  
Deploy new AWS assets, such as a new ECS task definition and service.

`verify-green`  
Verify newly deployes AWS assets, e.g., run regression tests suites.

`switch-to-blue`  
Redirect production traffic to the new AWS assets, e.g. route traffic to a new version of an ECS service.

`verify-blue`  
Verify the any modified AWS assets as a result of switching to blue.
After blue has been verified, rollbacks are no longer possible.

`after-verify-blue`  
Perform tasks after the switch to blue has been performed and verified. This is used to remove old
AWS resources that are no longer needed.

`finalize`  
Perform any final activities or clean up any resources.

### Rollback lifecycles
Rollback lifecycles will be triggered in the event of a failure during the normal lifecycles, up to and including `verify-blue`. After the `verify-blue` lifecycle completes, rollback are no longer possible.

`before-rollback`  
Perform any preliminary rollback activites, e.g. gather resources or telemetry on the failed deployment. 

`rollback`  
Restore any changes to the deployment, remove any resources that are not needed.

`verify-rollback`  
Verify the rollback was successful, e.g. by re-running tests.

`after-rollback`  
Perform any tasks after the rollback has been completed.
