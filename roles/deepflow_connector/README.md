# Role: deepflow_connector

Deploy a lightweight OpenTelemetry Collector bridge that scrapes DeepFlow metrics and writes the
selected L4/L7 protocol metrics into VictoriaMetrics.

## Key Variables

- `deepflow_connector_source_endpoint`
- `deepflow_connector_metric_keep_regex`
- `deepflow_connector_remote_write_url`
- `deepflow_connector_scrape_interval`

## Scope

- Supports metrics export only
- Does not export protocol logs
- Does not export traces
