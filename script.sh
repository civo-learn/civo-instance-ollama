#!/bin/bash

# ===========================================
# CONFIGURATION - Edit these variables as needed
# ===========================================
MODEL_NAME="llama2"     # The Ollama model to run
CUDA_GPU="0"            # GPU device to use (0, 1, etc.)
API_PORT="11434"        # Port for Ollama API (default is 11434)
# ===========================================

set -e

# Update packages
apt-get update

# Install required packages
apt install -y nvidia-cuda-toolkit curl

# Stop and disable fabric manager
systemctl stop nvidia-fabricmanager || true
systemctl disable nvidia-fabricmanager || true

# Disable NVLink for 1xH100
echo "blacklist nvidia_uvm" > /etc/modprobe.d/nvlink-denylist.conf
echo "options nvidia NVreg_NvLinkDisable=1" > /etc/modprobe.d/disable-nvlink.conf
update-initramfs -u

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Create systemd service for Ollama
cat > /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama Service
After=network.target

[Service]
Environment="CUDA_VISIBLE_DEVICES=${CUDA_GPU}"
# Make Ollama API accessible from any IP address
ExecStart=/usr/local/bin/ollama serve -l 0.0.0.0:${API_PORT}
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Create a script to output server information on boot
cat > /usr/local/bin/ollama_server_info.sh << 'EOF'
#!/bin/bash

# Wait for network to be fully up
sleep 10

# Get public IP address (try multiple methods)
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)

# Get API port from service file
API_PORT=$(grep -oP 'ExecStart=.*-l\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/ollama.service)
if [ -z "$API_PORT" ]; then
  API_PORT="11434"  # Default if not found
fi

# Get model name
MODEL_NAME=$(grep -oP 'Description=Run\s+\K[^\s]+' /etc/systemd/system/ollama-run-model.service)
if [ -z "$MODEL_NAME" ]; then
  MODEL_NAME="unknown"
fi

# Create info file
cat > /etc/ollama/server_info.txt << EOT
======================================================
OLLAMA SERVER INFORMATION
======================================================
Public IP Address: ${PUBLIC_IP}
API Port: ${API_PORT}
Default Model: ${MODEL_NAME}
API Endpoint: http://${PUBLIC_IP}:${API_PORT}/api/chat

To use this server:
1. Connect via API at: http://${PUBLIC_IP}:${API_PORT}/api
2. Example API call: curl -X POST http://${PUBLIC_IP}:${API_PORT}/api/generate -d '{"model":"${MODEL_NAME}", "prompt":"Hello world"}'
3. For monitoring: systemctl status ollama
======================================================
EOT

# Print to system log
cat /etc/ollama/server_info.txt > /dev/console
logger -t ollama-setup "Ollama server ready at http://${PUBLIC_IP}:${API_PORT}"

# Save IP information for future reference
echo "${PUBLIC_IP}" > /etc/ollama/public_ip.txt
echo "${API_PORT}" > /etc/ollama/api_port.txt
EOF

chmod +x /usr/local/bin/ollama_server_info.sh

# Create a service to output server info
cat > /etc/systemd/system/ollama-server-info.service << 'EOF'
[Unit]
Description=Output Ollama Server Information
After=network-online.target ollama.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ollama_server_info.sh
RemainAfterExit=yes
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Enable the info service
systemctl enable ollama-server-info.service

# Create directory for ollama information
mkdir -p /etc/ollama

# Enable the services to start on boot
systemctl daemon-reload
systemctl enable ollama.service

# Create a script to run model at first boot
cat > /usr/local/bin/run_ollama_model.sh << EOF
#!/bin/bash
sleep 30  # Give ollama service time to fully initialize
/usr/local/bin/ollama run ${MODEL_NAME}
EOF

chmod +x /usr/local/bin/run_ollama_model.sh

# Create a oneshot service to run the model at first boot
cat > /etc/systemd/system/ollama-run-model.service << EOF
[Unit]
Description=Run ${MODEL_NAME} on Ollama
After=ollama.service
Wants=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/run_ollama_model.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Enable the model service
systemctl enable ollama-run-model.service

echo "Setup complete! The system will now reboot to apply changes."
echo "After reboot, check /etc/ollama/server_info.txt for connection details."
echo "The server will run ${MODEL_NAME} on GPU ${CUDA_GPU} with API on port ${API_PORT}."

# Reboot is needed to apply the kernel module changes
reboot