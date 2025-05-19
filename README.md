# Civo-instance-ollama
This is a simple terraform repository that enables users to launch an Ollama instance on a single H100 GPU. 

## Getting started

- input your civo API key into a file named "terraform.tfvars" in the root directory
- e.g "civo_token = "YOUR_KEY"

To deploy simply run:

- terraform init
- terraform plan
- terraform apply

Once initally created. It will take about 15-30 minutes to setup and install. Post installation, the model you selected in the script.sh will download and serve. This will be dependant on the model you run. 

## Connecting to the Model

On server creation, all network configuration including the model endpoint is made avalaible in the file located /etc/ollama/server_info.txt and the instance system log. 

To monitor your Ollama installation you can run: systemctl status ollama

## Securing the model
This model is configured to a Civo Firewall, for production usecases you can easily specify firewall rules in civo_firewall-ingress.tf. Please configure this before go live. 

## Removing the entire deployment
If you'd like to remove the entire deployment, simply run:
- terraform destroy


## Future work
- Compatibility with other GPU sizes
- Request specific Ollama version
- Terraform tests
