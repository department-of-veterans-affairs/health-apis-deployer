# Load Balancer Rules

Load balancer rules are created and deleted by the deployer with every deployment. On creation, AWS views the priority in the request as a minimum value and does not allow
overlapping priorities. To prevent rules from stacking ontop of eachother in an undesirable order, the deployer treats priorities as "slots". These slots begin at 10 and
end at 1000, using increments of 10 (10, 20, 30, and so on). New applications may use any unused priority slot value.

#### Example Load Balancer Configurations in a `products/<product>.conf` file:
```
DU_LOAD_BALANCER_RULES[10]="/hello*"
DU_LOAD_BALANCER_RULES[20]="/hola*"
```

#### To determine available load-balancer slot values:
```
$ ./list-load-balancer-rules 
10 /hello* exemplar
20 /hola* exemplar
```

#### NOTES:
- Priorites are unique, no two rules may occupy the same priority value (If values will conflict with eachother, both values must change priorities).
- The `list-load-balancer-rules` script not only prints all load-balancer rules, it validates them and will print a failure reason if something is incorrect. This failure will also cause the deployer to fail a build/upgrade.
- The `list-load-balancer-rules` script prints in the following format: <priority> <rule> <application-name>

---

# Ingress Rules

Once a request makes it through the load-balancer, the ingress decides which pod/namespace to route the request to. Unlike the load-balancer though, ingresses do not have a
static priority. Kubernetes prioritizes them in descending order of length (longest to shortest) and routes on a first match basis. Therefore, ingresses are infinitely more
tricky to determine than load-balancer rules.


#### To determine if your ingress paths are okay:
1. Add some of your applications available paths (<application-name> <path>) to the deployers `ingress.tests' file (see example below):
```
# Exemplar
exemplar /hello
exemplar /hola
```

2. Run the deployers `list-ingress-rules` script:
```
$ ./list-ingress-rules
1 /fhir/v0/(dstu2|stu3|r4)/(AllergyIntolerance|Appointment|Condition|DiagnosticReport|Encounter|Immunization|Location|Medication|MedicationDispense|MedicationOrder|MedicationStatement|Observation|Organization|Patient|Practitioner|PractitionerRole|Procedure)($|/[^$].*|/[$]validate) data-query
2 /unifier-test/(fhir/v0/.*)/(metadata|.well-known/smart-configuration) unifier-kong
```

#### NOTES:
- The `list-ingress-rules` script uses the paths in `ingress.tests` to verify that all paths related to a specific application are being consumed by that application's ingress. If the script cannot determine a match or finds that a rule does not match its given application, it will `exit 1` and print the cause, ultimately making the deployer fail.
- The output of `list-ingress-rules` is as follows: <determined-priority> <rule-text> <application-name> 