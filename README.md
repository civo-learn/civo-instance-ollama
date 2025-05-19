# Civo-Ollama: Deploy LLM Inference on Civo Cloud with H100 GPUs

This comprehensive Terraform repository allows you to quickly deploy Ollama for Large Language Model inference on Civo Cloud with H100 GPUs. The setup automatically configures NVIDIA drivers, optimizes GPU settings, exposes API endpoints, and serves your chosen model with minimal configuration.

## Overview

This repository provisions a Civo instance with an H100 GPU and sets up Ollama to serve LLMs through a REST API. The deployment automatically:

- Configures CUDA drivers and toolkit
- Optimizes GPU settings for inference performance
- Installs and configures Ollama
- Sets up systemd services for reliability
- Creates convenient information outputs and monitoring
- Secures the deployment with firewall rules

## Getting Started

### Prerequisites

- Civo Cloud account with API access
- Terraform installed on your local machine

### Deployment Steps

1. Create a file named `terraform.tfvars` in the root directory with your Civo API key:
   ```
   civo_token = "YOUR_API_KEY"
   ```

2. Initialize and apply the Terraform configuration:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. Wait for the initial setup to complete (approximately 15-30 minutes). This includes:
   - Instance provisioning
   - CUDA installation and configuration
   - Ollama setup
   - Model downloading

## Configuration Options

The deployment can be customized by modifying the `script.sh` file. Key configurable parameters include:

```bash
MODEL_NAME="llama2"     # The Ollama model to run
CUDA_GPU="0"            # GPU device to use (0, 1, etc.)
API_PORT="11434"        # Port for Ollama API (default is 11434)
```

### Available Models

You can deploy any model supported by Ollama by changing the `MODEL_NAME` variable. Model download times will vary depending on the size.

## Accessing Your Model

### Finding Connection Details

After deployment completes, connection information is automatically generated and stored on the server at `/etc/ollama/server_info.txt`. This file contains:

- Public IP address
- API port
- Default model name
- Example API calls

You can also check the system log for this information after the instance boots.

### API Usage Examples

The Ollama API can be accessed using standard HTTP requests:

```bash
# Basic generation request
curl -X POST http://YOUR_SERVER_IP:11434/api/generate \
  -d '{"model":"llama2", "prompt":"Hello world"}'

# Chat completion
curl -X POST http://YOUR_SERVER_IP:11434/api/chat \
  -d '{"model":"llama2", "messages":[{"role":"user", "content":"Hello"}]}'
```

## System Management

### Monitoring Services

To check the status of the Ollama service:

```bash
systemctl status ollama
```

To view logs:

```bash
journalctl -u ollama
```

### System Architecture

The deployment creates three systemd services:

- `ollama.service` - Main Ollama API server
- `ollama-server-info.service` - Generates connection information
- `ollama-run-model.service` - Loads model on first boot

### NVIDIA Optimizations

The script implements several optimizations for H100 GPUs:

- Disables NVLink (optimized for single GPU setup)
- Configures appropriate CUDA settings
- Blacklists unnecessary modules

## Security Considerations

The default setup exposes the API endpoint to the internet, secured by a Civo Firewall. For production use, you should:

- Update the firewall rules in `civo_firewall-ingress.tf` to restrict access to trusted IPs
- Consider implementing authentication for API access
- Regularly update the system for security patches

## Removing the Deployment

To completely remove the deployment:

```bash
terraform destroy
```

This will terminate the instance and clean up all associated resources.

## Troubleshooting

If you encounter issues:

- Check `/etc/ollama/server_info.txt` for connection details
- Verify the service status with `systemctl status ollama`
- Look for errors in the logs with `journalctl -u ollama`
- Ensure your firewall rules allow access to the API port

## Future Work

- Add support for multi-GPU configurations
- Implement compatibility with various GPU types beyond H100
- Allow specification of Ollama version during deployment
- Add automated testing with Terraform testing frameworks
- Add support for containerized deployment
- Implement auto-scaling based on inference demand