package main

# Run with: conftest test environments/requests/*.yaml --policy policy/

max_allowed_cpu_cores := 8
max_allowed_memory_gi := 16
max_allowed_pods := 50
valid_environments := {"dev", "staging", "prod"}

deny[msg] {
	not input.team_name
	msg := "team_name is required"
}

deny[msg] {
	input.team_name
	not regex.match("^[a-z0-9-]{3,20}$", input.team_name)
	msg := sprintf("team_name '%v' must be lowercase alphanumeric with hyphens, 3-20 chars", [input.team_name])
}

deny[msg] {
	input.environment
	not valid_environments[input.environment]
	msg := sprintf("environment '%v' must be one of dev, staging, prod", [input.environment])
}

deny[msg] {
	input.cpu_limit_max
	to_number(trim_suffix(input.cpu_limit_max, "")) > max_allowed_cpu_cores
	msg := sprintf("cpu_limit_max '%v' exceeds max allowed (%v cores) for self-service namespaces", [input.cpu_limit_max, max_allowed_cpu_cores])
}

deny[msg] {
	input.max_pods
	input.max_pods > max_allowed_pods
	msg := sprintf("max_pods '%v' exceeds max allowed (%v) for self-service namespaces", [input.max_pods, max_allowed_pods])
}

deny[msg] {
	not input.owner_email
	msg := "owner_email is required for cost/ownership tracking"
}

deny[msg] {
	input.environment == "prod"
	msg := "prod environment requests require manual platform-team approval — this policy blocks automated self-service for prod; remove this rule once an approval gate is added to the workflow"
}
