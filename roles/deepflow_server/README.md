# Role: deepflow_server

Deploy DeepFlow server stack (deepflow-server + deepflow-app + ClickHouse + MinIO)
with Docker Compose managed by systemd.

## Usage

1. Ensure Docker is installed (`./docker.yml`) and `docker_enabled: true`.
2. Add hosts to a `deepflow` group with proper vars.
3. Run `./deepflow.yml -l deepflow`.

## Key Variables

- `deepflow_stack_dir` (default `/opt/deepflow-server`)
- `deepflow_data` (default `/data/deepflow`)
- `deepflow_server_grpc_port` (default `20035`)
- `deepflow_app_port` (default `20880`)
- `deepflow_s3_access_key`, `deepflow_s3_secret_key`

## Related

- `roles/infra/templates/caddy/Caddyfile` for TLS gRPC ingress
- `roles/infra/defaults/main.yml` (`deepflow_grpc_*` variables)
