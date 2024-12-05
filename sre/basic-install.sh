#!/bin/bash

# Environments
URL_PROM="https://github.com/prometheus/prometheus/releases/download/v2.53.3/prometheus-2.53.3.linux-amd64.tar.gz"
URL_NODE_EXP="https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz"
INSTALL_PATH="/usr/local/bin"
PROMETHEUS_SERVICE="/etc/systemd/system/prometheus.service"
NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"
PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"

# Password validation
clear
read -s -p "🔒 Enter the password for superuser commands: " PASSWD
echo
echo "$PASSWD" | sudo -S true 2> /dev/null
if [ $? -ne 0 ]; then
    echo "❌ Invalid password or permission issue."
    exit 1
fi

# Repository update and download files
clear
echo "🛬 Installing dependencies..."
sleep 2
echo "$PASSWD" | sudo -S apt update
echo "$PASSWD" | sudo -S apt install -y curl

clear
echo "🛬 Downloading files..."
sleep 2
curl -Lo /tmp/prometheus.tar.gz "$URL_PROM"
curl -Lo /tmp/node_exporter.tar.gz "$URL_NODE_EXP"

# Installation
clear
echo "🛬 Extracting files..."
sleep 2
TEMP_DIR=$(mktemp -d)

tar -xzf /tmp/prometheus.tar.gz -C "$TEMP_DIR"
PROM_BIN=$(find "$TEMP_DIR" -type f -name prometheus | head -n 1)
echo "$PASSWD" | sudo -S mv "$PROM_BIN" "$INSTALL_PATH"

tar -xzf /tmp/node_exporter.tar.gz -C "$TEMP_DIR"
NODE_BIN=$(find "$TEMP_DIR" -type f -name node_exporter | head -n 1)
echo "$PASSWD" | sudo -S mv "$NODE_BIN" "$INSTALL_PATH"

echo "$PASSWD" | sudo -S mkdir -p /etc/prometheus /var/lib/prometheus

echo "🛠️ Creating the prometheus.yml file..."
sleep 2
echo "$PASSWD" | sudo -S bash -c "cat > $PROMETHEUS_CONFIG" <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

# Service configuration
echo "🛠️ Configuring Prometheus service..."
sleep 2
echo "$PASSWD" | sudo -S bash -c "cat > $PROMETHEUS_SERVICE" <<EOF
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=$INSTALL_PATH/prometheus \
  --config.file=$PROMETHEUS_CONFIG \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries
  --storage.tsdb.retention.time=90d

[Install]
WantedBy=multi-user.target
EOF

echo "🛠️ Configuring Node Exporter service..."
sleep 2
echo "$PASSWD" | sudo -S bash -c "cat > $NODE_EXPORTER_SERVICE" <<EOF
[Unit]
Description=Node Exporter for Prometheus
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=$INSTALL_PATH/node_exporter

[Install]
WantedBy=multi-user.target
EOF

echo "🛠️ Creating users for the services..."
sleep 2
echo "$PASSWD" | sudo -S useradd --no-create-home --shell /bin/false prometheus
echo "$PASSWD" | sudo -S useradd --no-create-home --shell /bin/false node_exporter

echo "$PASSWD" | sudo -S chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

echo "🛠️ Enabling and starting services..."
sleep 2
echo "$PASSWD" | sudo -S systemctl daemon-reload
echo "$PASSWD" | sudo -S systemctl enable prometheus
echo "$PASSWD" | sudo -S systemctl start prometheus
echo "$PASSWD" | sudo -S systemctl enable node_exporter
echo "$PASSWD" | sudo -S systemctl start node_exporter

# Cleaning up
clear
echo "🛬 Cleaning up temporary files..."
sleep 2
rm -rf "$TEMP_DIR" /tmp/prometheus.tar.gz /tmp/node_exporter.tar.gz

echo "✅ Installation and configuration completed! Check the services with:"
echo "   sudo systemctl status prometheus"
echo "   sudo systemctl status node_exporter"
