# Timers

The Deploy provides the ability to define timers that are automatically managed as part of the 
deployment process.
Timers will invoke an HTTP endpoint, typically the Blue load balancer for the environment.

Timers provide a simple way to define period processing that triggered _once_ per environment.
This solves the _multiple trigger_ problem that can arise from timers defined by the application
or as Kubernetes Cronpods.

Deployer timers support deploy-time substitution via the standard deployer mechanism and 
execution-time substitution via secrets defined using AWS Parameter Store.
See [Callculon](https://github.com/department-of-veterans-affairs/lighthouse-callculon) on how to
AWS Parameter Store secrets.

See [an example timer](deployer-tests/timer-deployer.json).

See [AWS Scheduled Event cron expression syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html).


## Problem
Timers are a reoccurring need of the different products on the platform. 
The common practice is to either:
- Have a Spring Boot application register a `@Scheduled` method on a controller.
- Create a protected management REST endpoint and a Kubernetes Cronpod to periodically invoke the endpoint.

Because our implementation of Kubernetes relies on independent clusters per Availability Zone, both approaches suffer from duplicated timers.
To work around the duplication, the common solutions are:
- Build logic into the application to ensure concurrent timer expirations result in a single execution by using an optimistic database lock.  
  _This is complex and must be re-implemented on each application._
- Only the deploy application to a single AZ.  
  _This is not acceptable for reliability and fault tolerance._

## Goal
- Create a reusable solution to easily allow products to create timers that fire once-per-environment.
- Minimize duplication of effort.
- Simplify application development.
- Standardize best practices for timers.


## Why HTTP-based timers

### Standardize on REST
The Deployer standardizes timers as protected HTTP management endpoints.

- This moves timers out of the application. Applications focus their responsibility of executing 
  business logic, not determining when to execute. The when to execute responsibility is moved to
  the deployment unit, where it become configuration.
- It gives product maintainers an escape hatch that allows the timer to be manually invoked for
  any unscheduled reason. This provides better response/recovery options in an outage situation 
  or during problem resolution.

##### Example management endpoint
```
GET https://blue.production.lighthouse.va.gov/facilities/management/facilities/collect
```

### Externalized timers
Timers are externalized from Kubernetes and able to span the multiple Kubernetes clusters per
environment.
AWS Lambda and Event Rules are used to implement timers.
The [Callculon](https://github.com/department-of-veterans-affairs/lighthouse-callculon) lambda 
provides the machine necessary to perform HTTP requests. 
AWS Event rules (and rule targets) provides the scheduling and HTTP request configuration. 
When an event rule expires based on the cron schedule, its HTTP request configuration is 
passed to the lambda for execution.

## Timer Lifecycle

- Timers are removed at the start of deployment, before the application is removed from the
  first Availability Zone
- Timers are added at the end of the deployment, after the last Availability Zone is retattached
  to the blue load balancer
  
> #### ATTENTION
> Timers schedule to execute during deployment will be skipped.
>
> For example, if you have  timer schedule to execute at 9:00 AM every morning and start a deployment
> for you product at 8:59, the timer will be removed before it expires and restored after the 
> expiration time. It will not be fired. However, since this is just invoking a management endpoint,
> you can manually invoke it at your discretion.