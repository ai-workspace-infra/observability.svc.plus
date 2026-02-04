# Role: deepflow_server

Deploy DeepFlow control plane (`deepflow-server` + `deepflow-app`) with Docker Compose managed by systemd.

This role expects backend dependencies from separate roles:

- `deepflow_mysql`
- `deepflow_clickhouse_s3`

## Usage

1. Ensure Docker is installed (`./docker.yml`) and `docker_enabled: true`.
2. Run backend roles first, then this role (see `deepflow.yml`).

## Key Variables

- `deepflow_server_grpc_port` (default `20035`)
- `deepflow_server_http_port` (default `20417`)
- `deepflow_app_port` (default `20880`)
- `deepflow_clickhouse_addr` (default `host.docker.internal:19000`)
- `deepflow_s3_endpoint` (default `http://host.docker.internal:19090`)
