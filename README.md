# Grafana Stack on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/template/8TLSQD?referralCode=IFlm92)

## What is this template

This template deploys a complete Grafana observability stack on Railway with just one click! The stack includes four integrated services:

- **Grafana**: The leading open-source analytics and monitoring solution
- **Loki**: A horizontally-scalable, highly-available log aggregation system
- **Prometheus**: A powerful metrics collection and alerting system
- **Tempo**: A high-scale distributed tracing backend

This template is perfect for teams who need a comprehensive observability solution for their railway project without the hassle of manual configuration and infrastructure management.

### Key Features

- **Pre-configured Integration**: _All services come pre-connected_, so Grafana is ready to query your data immediately.
- **Persistent Storage**: All four services use Railway volumes to ensure your data, dashboards, and configurations persist between updates and deploys.
- **Version Control**: Pin specific Docker image versions for each service using environment variables.
- **Customizable**: Fork the repository to customize configuration files for any service. You can take full control and edit anything you'd need to as you scale.
- **One-Click Deploy**: Get a complete Grafana-based observability stack running in minutes.

## Quick Start Guide

1. Click the "Deploy on Railway" button at the top of this page
2. Enter your desired Grafana admin username in the `GF_SECURITY_ADMIN_USER` variable
3. Leave all other variables at their defaults (or customize as needed)
4. Wait for your stack to deploy (this typically takes 3-5 minutes)
5. Navigate to the Grafana URL provided by Railway
6. Log in with your admin username and the auto-generated password found in the `GF_SECURITY_ADMIN_PASSWORD` environment variable
7. Hook up your applications to the datasources.
8. Create dashboards, alerts, and explore your data in Grafana!

## Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GF_SECURITY_ADMIN_USER` | Username for the Grafana admin account | Required input |
| `GF_SECURITY_ADMIN_PASSWORD` | Password for the Grafana admin account | Auto-generated secure string |
| `GF_DEFAULT_INSTANCE_NAME` | Name of your Grafana instance | `Grafana on Railway` |
| `GF_INSTALL_PLUGINS` | Comma-separated list of Grafana plugins to install. If your Grafana service has an older value, see [Remove the Angular plugins from an existing Grafana volume](#remove-the-angular-plugins-from-an-existing-grafana-volume) | `grafana-clock-panel` |

### Internal Service URLs

The Grafana service exposes these environment variables that you can reference in your other Railway applications to easily send data to your observability stack:

| Variable | Description | Usage |
|----------|-------------|-------|
| `LOKI_INTERNAL_URL` | Internal URL for the Loki service | Use in your applications to send logs to and query Loki |
| `PROMETHEUS_INTERNAL_URL` | Internal URL for the Prometheus service | Use in your applications to send metrics to and query Prometheus |
| `TEMPO_INTERNAL_URL` | Internal URL for the Tempo service | Use in your applications to query Tempo |

These variables make it easy to configure your other Railway services to send telemetry data to your observability stack.

Tempo also exposes a few variables to make it easier to push tracing information to the service using either HTTP or GRPC

| Variable | Description | Usage |
|----------|-------------|-------|
| `INTERNAL_HTTP_INGEST` | Internal HTTP ingest server URL for Tempo | Use in your applications to send traces to tempo via HTTP |
| `INTERNAL_GRPC_INGEST` | Internal GRPC ingest server URL for Tempo | Use in your applications to send traces to tempo via GRPC |

### Version Control

Each service has its own `VERSION` environment variable that can be set independently in each service's settings in the Railway dashboard:

- **Grafana Service**: Set `VERSION` to control the Grafana Docker image tag
- **Loki Service**: Set `VERSION` to control the Loki Docker image tag
- **Prometheus Service**: Set `VERSION` to control the Prometheus Docker image tag
- **Tempo Service**: Set `VERSION` to control the Tempo Docker image tag

By default, all services use the `latest` tag, but you can pin specific versions for stability:

Examples:
- Grafana: `VERSION=11.5.2`
- Loki: `VERSION=3.4.2`
- Prometheus: `VERSION=v3.2.1`
- Tempo: `VERSION=2.9.0`

This allows you to update each component independently as needed.

> **⚠️ Note on Tempo v2.10.0**: There is a known issue with Tempo v2.10.0 where the `compactor` configuration block is not recognized, causing startup failures. This template is pinned to v2.9.0 until this issue is resolved in a future release.

## Project Structure & Services

This template deploys four interconnected services:

### Grafana
- The central visualization and dashboarding platform
- Pre-configured with connections to all other services
- Persistent volume for storing dashboards, users, and configurations
- Installs the plugins listed in `GF_INSTALL_PLUGINS` when it starts
- Exposes internal URLs for other Railway services to connect to Loki, Prometheus, and Tempo

### Prometheus
- Time-series database for metrics collection
- Configured with sensible defaults for monitoring
- Persistent volume for metrics data

### Loki
- Log aggregation system designed to be cost-effective
- Horizontally scalable architecture
- Persistent volume for log storage
- Loki deletes logs after 31 days. To keep them longer or shorter, change `limits_config.retention_period` in `loki/loki.yml`

### Tempo
- Distributed tracing system for tracking requests across services
- High-performance trace storage
- Persistent volume for trace data

All services are deployed using official Docker images and configured to work together seamlessly.

## Connecting Your Applications

### Using [Locomotive](https://railway.com/template/jP9r-f) for Loki

You can easily ingest *all* of your railway logs into Loki from *any* service using [Locomotive](https://railway.com/template/jP9r-f). Just spin up their template, drop in your Railway API key, the ID of the services you want to monitor, and a link to your new Loki instance and logs will start flowing! no code changes needed anywhere!

### Using OpenTelemetry libraries for Tempo 

Tempo is a bit different than both Prometheus and Loki in that exposes separate GRPC and HTTP servers on ports `:4317` and `:4318` respectively specifically for ingesting your tracing data or "spans".

When configuring your application to send traces to Tempo, please use one of the preconfigured variables in the Tempo service: `INTERNAL_HTTP_INGEST` or `INTERNAL_GRPC_INGEST`.

Another thing to note is that the ingest API endpoint for the HTTP server is `/v1/traces`. For a working example of this in a node.js express API, see `/examples/api/tracer.js` in our GitHub repository. Load the file before the application with `node --import ./tracer.js index.js`, as the example's `start` script does.

### Using otherwise standard observability tooling

To send data from your other Railway applications to this observability stack:

1. In your application's Railway service, add environment variables that reference the internal URLs:
   ```
   LOKI_URL=${{Grafana.LOKI_INTERNAL_URL}}
   PROMETHEUS_URL=${{Grafana.PROMETHEUS_INTERNAL_URL}}
   TEMPO_URL=${{Grafana.TEMPO_INTERNAL_URL}}
   ```
2. Configure your application's logging, metrics, or tracing libraries to use these URLs
3. Your application data will automatically appear in your Grafana dashboards

### Using the Docker Compose stack

Prometheus, Loki, Tempo, and the example API have no authentication. For that reason, `docker-compose.yml` publishes their ports on the `127.0.0.1` address of the Docker host only: `9090`, `3100`, `3200`, `4317`, `4318`, and `9091`.

From the Docker host, connect to `127.0.0.1`. Do not use `localhost` or the network address of the host. The ports are not published on the IPv6 loopback address `::1`. A client that resolves `localhost` to `::1` first and does not retry on IPv4 cannot connect.

Services in the same Compose project still use the service names, for example `http://loki:3100` and `http://tempo:4318`. To connect a container that is outside the project, attach it to the network of the project and use the same service names and ports.

Docker does not publish these ports on the other addresses of the host, so a client on another machine cannot connect through them. Docker Engine older than 28.0.0 has one exception: a machine on the same network segment as the Docker host can reach a port that is published on `127.0.0.1`. See [Port publishing and mapping](https://docs.docker.com/engine/network/port-publishing/) in the Docker documentation.

To accept connections from other machines on purpose, change `127.0.0.1` in the `ports` entry of the service and port that you want to open, for example `"127.0.0.1:4318:4318"` under `tempo`. Put your own access control in front of the port first.

The Railway template does not use `docker-compose.yml`.

## Customizing Your Stack

To customize the configuration of Loki, Prometheus, or Tempo:

1. Fork the [GitHub repository](https://github.com/yourusername/grafana-railway-template)
2. Modify the configuration files in their respective directories
3. In Railway, disconnect the service you want to customize
4. Reconnect the service to your forked repository
5. Deploy the updated service

The pre-configured Grafana connections will continue to work with your customized services.

## Set the Grafana admin password for Docker Compose

`docker-compose.yml` needs a Grafana admin password in `GF_SECURITY_ADMIN_PASSWORD`. Until you set it, any `docker compose` command that loads this file stops with an error. That includes `docker compose up`, `docker compose ps`, and `docker compose down`.

Put the password in a `.env` file next to `docker-compose.yml`. Git ignores that file.

```
GF_SECURITY_ADMIN_PASSWORD='<your unique password>'
```

Keep the single quotes. Compose expands a `$` in an unquoted value, so a password that contains `$` would change.

The Railway template does not use `docker-compose.yml`. Railway generates the password for you.

Grafana saves the admin password in the `grafana_data` volume the first time it starts. After that, it ignores `GF_SECURITY_ADMIN_PASSWORD`. A volume created from an older copy of `docker-compose.yml` keeps the password that was published in this repository. To change the password on an existing volume, set the new value in `.env` and run:

```
docker compose up -d grafana
docker compose exec grafana sh -c 'grafana cli admin reset-admin-password "$GF_SECURITY_ADMIN_PASSWORD"'
```

The second command reads the new password from the container's environment, so the password does not appear on your command line.

## Remove the Angular plugins from an existing Grafana volume

Older copies of this repository installed four plugins by default: `grafana-simple-json-datasource`, `grafana-piechart-panel`, `grafana-worldmap-panel`, and `grafana-clock-panel`. Grafana 11 disables Angular support by default. With that default, it refuses the first three and logs `Refusing to initialize plugin because it's using Angular` for each one every time it starts. The default is now `grafana-clock-panel`.

Grafana installs plugins into the `grafana_data` volume, and the volume keeps a plugin after it leaves `GF_INSTALL_PLUGINS`. A volume that ran the old default still has the three plugins, so the errors continue.

To remove them from the Docker Compose stack, first get the new `docker-compose.yml`, for example with `git pull`. A Grafana container keeps the environment it was created with. Each time it starts, its start script runs the plugin installer for every entry in `GF_INSTALL_PLUGINS`, so it installs again any plugin that is on the list and missing from the volume. The first command recreates the container with the new list, so the restart at the end does not install the three plugins again. Run:

```
docker compose up -d grafana
docker compose exec grafana grafana cli plugins remove grafana-simple-json-datasource
docker compose exec grafana grafana cli plugins remove grafana-piechart-panel
docker compose exec grafana grafana cli plugins remove grafana-worldmap-panel
docker compose restart grafana
```

On Railway, look at `GF_INSTALL_PLUGINS` in the variables of the Grafana service. If it still has the older four-plugin value, set it to `grafana-clock-panel`. Then run `grafana cli plugins remove <id>` inside the Grafana container for each of the three plugins, and restart the service.

## Additional Resources

- [Locomotive: a loki transport for railway services](https://railway.com/template/jP9r-f)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Grafana Community Forums](https://community.grafana.com/)
- [Grafana Plugins Directory](https://grafana.com/grafana/plugins/)

---

Developed and maintained by [Mykal](https://mykal.codes). For issues or suggestions, please open an issue on the [GitHub repository](https://github.com/MykalMachon/grafana-stack-railway).
