# health-apis-deployer

This project is the home for the health-apis CD/CI pipeline.
This pipeline is used for automatic building, testing, and blue-green-gray deployments.
**_health-apis applications refers to Jargonaut(Java Argonaut Implementation), Mr. Anderson, and IDS_**  

The pipeline is initially triggered in one of two ways
- a successful jenkins build of the health-apis project
- a manual launch of the deployer jenkins job

Upon recieving this trigger, a unique docker container known as an _Upgraderator_ is built, and pushed to our docker cloud registry.

## Whats an Upgraderator?

An _Upgraderator_ contains the following configurations and functionalities:

##### health-apis version number
...
##### health-apis application.properties
...
##### environment configurations
...
##### openshift deployment-configs
...
##### openshift service-configs
...
##### openshift autoscaling-configs
...
##### template files
...

Upgraderator containers also contains the following scripts that perform the legwork of the CD/CI process:

##### `upgraderator.sh`
...
##### `deleterator.sh`
...
##### `blue-green.sh`
...
