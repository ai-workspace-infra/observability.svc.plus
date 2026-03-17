# Role: deepflow_clickhouse_s3

Deploy ClickHouse backend for DeepFlow with Docker Compose managed by systemd.

The default layout is optimized for short-term DeepFlow storage. MinIO/S3 can be disabled when the
deployment only needs local short-retention ClickHouse.

## Key Variables

- `deepflow_clickhouse_tcp_port` (default `19000`)
- `deepflow_clickhouse_http_port` (default `18123`)
- `deepflow_minio_api_port` (default `19090`)
- `deepflow_s3_access_key` / `deepflow_s3_secret_key`
- `deepflow_clickhouse_retention_hours` (default `24`)
- `deepflow_s3_enabled` (default `true`)
