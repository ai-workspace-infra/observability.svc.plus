# Role: deepflow_clickhouse_s3

Deploy ClickHouse + MinIO(S3) backend for DeepFlow with Docker Compose managed by systemd.

## Key Variables

- `deepflow_clickhouse_tcp_port` (default `19000`)
- `deepflow_clickhouse_http_port` (default `18123`)
- `deepflow_minio_api_port` (default `19090`)
- `deepflow_s3_access_key` / `deepflow_s3_secret_key`
