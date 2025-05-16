cd ../terraform
rm -f terraform.tfvars
web_public_ip=$(terraform output -raw eip)
terraform destroy -var "my_ip=192.168.0.1/32" -var="aws_az=sa-east-1a" -var="aws_region=sa-east-1" -auto-approve -lock=false
