#!/bin/bash

# ===========================================
# CONFIGURATION - Edit these variables as needed
# ===========================================
MODEL_NAME="llama3"     # The Ollama model to pull and make available
CUDA_GPU="0"            # GPU device to use (0, 1, etc.)
API_PORT="11434"        # Port for Ollama API (default is 11434)
# ===========================================

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Pipestatus: a pipeline's return status is the value of the last command to exit with a non-zero status,
# or zero if all commands in the pipeline exit successfully.
set -euo pipefail

echo "Starting Ollama setup script..."

# Update packages
echo "Updating package lists..."
apt-get update -y

# Install required packages
echo "Installing required packages (curl, nvidia-cuda-toolkit, sudo)..."
# Ensure sudo is installed, as it's used in the pull script
apt-get install -y curl nvidia-cuda-toolkit sudo

# Stop and disable fabric manager (specific to some NVIDIA setups)
echo "Stopping and disabling nvidia-fabricmanager..."
systemctl stop nvidia-fabricmanager || true # Continue if already stopped or not present
systemctl disable nvidia-fabricmanager || true

# Disable NVLink for 1xH100 (specific to some NVIDIA setups)
echo "Configuring NVLink settings..."
echo "blacklist nvidia_uvm" > /etc/modprobe.d/nvlink-denylist.conf
echo "options nvidia NVreg_NvLinkDisable=1" > /etc/modprobe.d/disable-nvlink.conf
echo "Updating initramfs..."
update-initramfs -u

# Install Ollama
echo "Installing Ollama..."
# The install script should create the 'ollama' user and group.
curl -fsSL https://ollama.com/install.sh | sh
echo "Ollama installation script finished."

# Create directory for ollama information and configurations
mkdir -p /etc/ollama

# Create systemd service for Ollama
# This service will run ollama serve as the 'ollama' user.
echo "Creating systemd service file for ollama (ollama.service)..."
cat > /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3
Environment="HOME=/usr/share/ollama"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=0.0.0.0" # Listen on all interfaces
Environment="OLLAMA_PORT=${API_PORT}"
Environment="CUDA_VISIBLE_DEVICES=${CUDA_GPU}"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models" # Standard models path

[Install]
WantedBy=multi-user.target
EOF

# Create a script to pull the specified Ollama model
# This script will be run by the ollama-pull-model.service
# It now uses 'sudo -u ollama' to execute ollama commands.
echo "Creating script to pull the Ollama model (/usr/local/bin/pull_ollama_model.sh)..."
cat > /usr/local/bin/pull_ollama_model.sh << EOF
#!/bin/bash
set -euo pipefail

# Configuration passed from the main script
TARGET_MODEL_NAME="${MODEL_NAME}"
OLLAMA_USER="ollama" # Define the user to run ollama commands as

echo "Attempting to pull Ollama model: \${TARGET_MODEL_NAME} as user \${OLLAMA_USER}..."

# Ensure ollama is in PATH for the script's execution context (and for sudo)
# It's generally better for sudo to find ollama via the ollama user's PATH or an absolute path.
# /usr/local/bin/ollama is the typical install location.

# Wait for Ollama server to be ready.
# The 'ollama list' command will be run as the ollama user.
MAX_RETRIES=12 # Approx 1 minute (12 * 5 seconds)
RETRY_COUNT=0
echo "Waiting for Ollama server to become responsive..."
# Note: 'sudo -u' inherits a minimal PATH. Explicitly call /usr/local/bin/ollama.
# Or ensure ollama user's .bashrc or .profile sets up PATH correctly if sudo -i is used.
# For simplicity, using absolute path to ollama for sudo commands.
while ! sudo -u "\${OLLAMA_USER}" HOME=/usr/share/ollama /usr/local/bin/ollama list > /dev/null 2>&1; do
    RETRY_COUNT=\$((RETRY_COUNT + 1))
    if [ "\$RETRY_COUNT" -gt "\$MAX_RETRIES" ]; then
        echo "Ollama server not responding after \$MAX_RETRIES retries (when checked as user \${OLLAMA_USER}). Exiting pull script."
        logger -t ollama-pull-model "Failed: Ollama server not responding after \$MAX_RETRIES retries (checked as \${OLLAMA_USER})."
        exit 1
    fi
    echo "Ollama server not ready yet (attempt \$RETRY_COUNT/\$MAX_RETRIES), retrying in 5 seconds..."
    sleep 5
done
echo "Ollama server is responsive."
logger -t ollama-pull-model "Ollama server is responsive. Proceeding to pull model as user \${OLLAMA_USER}."

# The ollama CLI communicates with the running ollama serve instance
echo "Pulling model \${TARGET_MODEL_NAME} as user \${OLLAMA_USER}..."
# Explicitly set HOME for the sudo command to ensure ollama knows where to store models for the ollama user.
if sudo -u "\${OLLAMA_USER}" HOME=/usr/share/ollama /usr/local/bin/ollama pull "\${TARGET_MODEL_NAME}"; then
    echo "Successfully pulled model \${TARGET_MODEL_NAME}."
    logger -t ollama-pull-model "Successfully pulled model \${TARGET_MODEL_NAME} as user \${OLLAMA_USER}."
else
    PULL_EXIT_CODE=\$?
    echo "Failed to pull model \${TARGET_MODEL_NAME}. Exit code: \$PULL_EXIT_CODE"
    logger -t ollama-pull-model "Error: Failed to pull model \${TARGET_MODEL_NAME} as user \${OLLAMA_USER}. Exit code: \$PULL_EXIT_CODE"
    exit \$PULL_EXIT_CODE
fi

echo "Finished attempting to pull model \${TARGET_MODEL_NAME}."
EOF
chmod +x /usr/local/bin/pull_ollama_model.sh

# Create a systemd service to pull the model
# This runs once after ollama.service has started.
# It now runs as root, and the script it calls uses 'sudo -u ollama'.
echo "Creating systemd service file for pulling the model (ollama-pull-model.service)..."
cat > /etc/systemd/system/ollama-pull-model.service << EOF
[Unit]
Description=Pull ${MODEL_NAME} for Ollama
After=ollama.service
Requires=ollama.service

[Service]
Type=oneshot
# Run the script as root. The script itself will use 'sudo -u ollama'.
User=root
Group=root
ExecStart=/usr/local/bin/pull_ollama_model.sh

[Install]
WantedBy=multi-user.target
EOF

# Create a script to output server information on boot
# This script uses the configuration variables directly.
echo "Creating script to output server information (/usr/local/bin/ollama_server_info.sh)..."
cat > /usr/local/bin/ollama_server_info.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Gathering server information..."

# Get public IP address (try multiple methods, with timeouts)
PUBLIC_IP=""
PUBLIC_IP=\$(curl --max-time 5 -s https://api.ipify.org || curl --max-time 5 -s https://ifconfig.me || curl --max-time 5 -s https://icanhazip.com || hostname -I | awk '{print \$1}' || echo "<unknown_or_private>")
if [[ -z "\$PUBLIC_IP" || "\$PUBLIC_IP" == "<unknown_or_private>" ]]; then
    PUBLIC_IP="<not_found_check_network_or_use_hostname_I>"
fi


# Use configured values passed from the main setup script
CONFIG_API_PORT="${API_PORT}"
CONFIG_MODEL_NAME="${MODEL_NAME}"

echo "Public IP determined as: \${PUBLIC_IP}"
echo "API Port: \${CONFIG_API_PORT}"
echo "Model: \${CONFIG_MODEL_NAME}"

# Create info file
mkdir -p /etc/ollama # Ensure directory exists
echo "Writing server info to /etc/ollama/server_info.txt..."
cat > /etc/ollama/server_info.txt << EOT_INFO
======================================================
OLLAMA SERVER INFORMATION
======================================================
Public IP Address: \${PUBLIC_IP}
API Port: \${CONFIG_API_PORT}
Default Model to be available: \${CONFIG_MODEL_NAME}
(Model pull is attempted by ollama-pull-model.service. Check its status with 'systemctl status ollama-pull-model.service')

API Endpoint: http://\${PUBLIC_IP}:\${CONFIG_API_PORT}/api

To use this server:
1. Connect via API at: http://\${PUBLIC_IP}:\${CONFIG_API_PORT}/api
2. Example API call:
   curl -X POST http://\${PUBLIC_IP}:\${CONFIG_API_PORT}/api/generate -d '{"model":"\${CONFIG_MODEL_NAME}", "prompt":"Why is the sky blue?"}'
3. Check Ollama service status: systemctl status ollama.service
4. Check model pull status: journalctl -u ollama-pull-model.service
5. List locally available models (run as root or ollama user):
   sudo -u ollama /usr/local/bin/ollama list
   /usr/local/bin/ollama list
======================================================
EOT_INFO

# Print to system log and console
echo "Displaying server info on console..."
cat /etc/ollama/server_info.txt > /dev/console
logger -t ollama-setup "Ollama server setup info: Public IP: \${PUBLIC_IP}, API Port: \${CONFIG_API_PORT}, Model: \${CONFIG_MODEL_NAME}. Check /etc/ollama/server_info.txt"

echo "Server information script finished."
EOF
chmod +x /usr/local/bin/ollama_server_info.sh

# Create a service to output server info
echo "Creating systemd service for outputting server info (ollama-server-info.service)..."
cat > /etc/systemd/system/ollama-server-info.service << 'EOF'
[Unit]
Description=Output Ollama Server Information
After=network-online.target ollama-pull-model.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ollama_server_info.sh
RemainAfterExit=no 
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable services
echo "Reloading systemd daemon and enabling services..."
systemctl daemon-reload
systemctl enable ollama.service
systemctl enable ollama-pull-model.service
systemctl enable ollama-server-info.service

echo ""
echo "================================================================================"
echo "Ollama setup script complete."
echo "The system will now REBOOT to apply kernel module changes for NVIDIA."
echo "After reboot:"
echo "1. Ollama service will start (ollama.service)."
echo "2. The model '${MODEL_NAME}' will be pulled (ollama-pull-model.service)."
echo "   You can check its status with: systemctl status ollama-pull-model.service"
echo "   And logs with: journalctl -u ollama-pull-model.service"
echo "3. Server connection details will be in /etc/ollama/server_info.txt and on the console."
echo "Ollama will serve on GPU ${CUDA_GPU} with API on port ${API_PORT}."
echo "================================================================================"
echo ""
echo "Rebooting in 10 seconds..."
sleep 10
reboot
