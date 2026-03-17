# Role: deepflow_agent

Deploy DeepFlow agent in one of three modes:

- `binary + systemd`
- `docker`
- `k8s` manifest rendering

## Key Variables

- `deepflow_agent_mode` (`binary`, `docker`, `k8s`)
- `deepflow_agent_profile` (`lite`, `full`)
- `deepflow_agent_grpc_endpoint`
- `deepflow_agent_download_url`
- `deepflow_agent_binary_path`

## Default Lightweight Profile

The default `lite` profile keeps `pcap` enabled and disables:

- built-in `vector`
- other optional non-core plugins

## Notes

- `k8s` mode renders a DaemonSet manifest and only applies it when `deepflow_agent_k8s_apply: true`
- `docker` mode requires `docker_enabled: true`
