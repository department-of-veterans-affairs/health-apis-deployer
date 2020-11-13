# timer

Add [Callculon](https://github.com/department-of-veterans-affairs/lighthouse-callculon) web-based timers to your deployment.

## Activation
Requires files
- `timer-${name}.json`

## Substitution
- `timer-${name}.json`

## Configuration
### `timer-daily-greeting.json`
Example
```
{
  "name": "daily-greeting",
  "deployment": {
    "enabled": true,
    "cron": "${TIMER_DAILY_CRON}"
  },
  "request": {
    "protocol": "HTTPS",
    "hostname": "${BLUE_LOAD_BALANCER_NAME}",
    "port": 443,
    "path": "/exemplar/hello",
    "method": "GET"
  },
  "notification": {
    "slack": {
      "webhook": "aws-secret(/dvp/slack/liberty)",
      "channel": "shanktovoid",
      "onFailure": true,
      "onSuccess": true
    }
  }
}
```
You may specify as many timers as you need. Details of the timer configuration are [here](https://github.com/department-of-veterans-affairs/lighthouse-callculon).

## Lifecycles
- `initialize`
  - Performs substitution on `timer-${name}.json` files
  - Verifies `${ENVIRONMENT}.testvars` is present
- `deploy-green`
  - Removes all timers for the product
  - Adds new timers for the product

### Rollback Lifecycles
- none