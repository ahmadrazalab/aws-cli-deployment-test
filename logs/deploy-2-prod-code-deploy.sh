# GIT CREDS
export GIT_USERNAME=TEST
export GIT_VALID_TOKEN=TEST
export DEPLOYMENT_TAG=TEST

# Static Variables

# Set environment variables for AMI name and description
export AMI_NAME="$DEPLOYMENT_TAG" #need to change everytime
export AMI_DESCRIPTION="$DEPLOYMENT_TAG"

# EC2 ID for deployment detup
export EC2_USER=root
export PP_INSTANCE_ID="TEST"
export PROD_INSTANCE_ID="TEST" ## FOR PROD SERVER ONLY

# Set environment variables for launch template
export LAUNCH_TEMPLATE_ID="TEST"

# Replace YOUR_TARGET_GROUP_ARN with the ARN of your target group
export ASG_NAME="TEST"
export ALB_LISTENER_ARN=TEST

## PP TG arn for healthy status check
export PP_TG_ARN="TEST"
export PROD_TG_ARN="TEST"



# Wait for the instance to reach 2/2 status checks passed
aws ec2 wait instance-status-ok --instance-ids $PROD_INSTANCE_ID

# Retrieve the public IP address of the instance
public_ip_prod=$(aws ec2 describe-instances --instance-ids $PROD_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo $public_ip_prod

# CODE DEPLOYMENT PROCESS : 

# SSH into the PP EC2 instance and execute commands
ssh -o StrictHostKeyChecking=no $EC2_USER@$public_ip_prod << EOF
  echo "Code Fetch and swith branch"
  cd /var/www/html-page/
  git remote remove origin
  git config --global --add safe.directory /var/www/html-page
  git stash
  git remote add origin https://$GIT_USERNAME:$GIT_VALID_TOKEN@github.com/ahmad-paytring/html-page.git
  git fetch --all
  git checkout tags/$DEPLOYMENT_TAG
  git remote remove origin
  ls -la
  service nginx restart
EOF

echo "Code Successfully Deployed "
sleep 5