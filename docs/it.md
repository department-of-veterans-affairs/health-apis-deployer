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