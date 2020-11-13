# it

Add integration testing to your deployment

## Activation
Requires files
- `test.conf`

## Substitution
- none

## Configuration
### `test.conf`
Example
```
export TEST_IMAGE=vasdvp/health-apis-exemplar-deployment-test:$EXEMPLAR_VERSION
```
This file must export the Docker test image that will be used to verify the deployment.

### `${ENVIRONMENT}.testvars`
Example
```
#encrypted 2
PATIENT_ID=ApRvT+L8M34Bpdkpa3m/e8UUDYACeRDtVtrgqNFTPK0=
TOKEN=SibqSR77qPRRn33DEAaOQrmZ/muKgxJS0rIGMLbp7TI=
```
This is a [Docker environment variables file](https://docs.docker.com/compose/env-file/), specified per environment. You will need one file for every environment you deploy into, e.g. `qa.testvars`, `staging.testvars`, and `production.testvars`
This file is
- encrypted using the Deployer Toolkit
- contains literals values with no substitution special character handling

## Test images
Test images will be invoked during the build to verify the deployment in two modes, identified as a single argument to your container.
- `regression-test` - Perform a full regression against the product in a safe manner without disrupting production traffic. 
- `smoke-test` - Perform a quick sanity check against the product in production. Smoke tests should execute quickly.

For example,
```
docker run [environment variables] $TEST_IMAGE regression-test
```

#### Pass or Fail
Test images will indicate tests passed or failed by the exit status code.
- Exit `0` to indicate success
- Exit non-zero to indicate failure

#### Environment
The test image will be passed every environment variable in your `${ENVIRONMENT}.testvars` file along with the following additional envionrment variables.
- `DEPLOYMENT_ENVIRONMENT` - The environment you are being deployed, e.g. `qa`, `staging-lab`, `production`.
- `DEPLOYMENT_ID` - The unique ID of this deployment.
- `DEPLOYMENT_PRODUCT` - The product name.
- `DEPLOYMENT_TEST_PROTOCOL` - The HTTP protocol to use when accessing your service on the ALB. Either `http` or `https`.
- `DEPLOYMENT_TEST_HOST` - The ALB hostname where your service is deployed, e.g. `green.qa.lighthouse.va.gov`
- `DEPLOYMENT_TEST_PORT` - The HTTP port your service is exposed on.


## Lifecycles
- `validate`
  - Verifies `TEST_IMAGE` is defined
  - Verifies `${ENVIRONMENT}.testvars` is present
- `verify-green`
  - Executes `regression-test`
- `verify-blue`
  - Executes `smoke-test`

### Rollback Lifecycles
- none