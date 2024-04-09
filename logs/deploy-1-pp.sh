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


########## Deployment started in PP SERVER###############

# Start the instance
aws ec2 start-instances --instance-ids $PP_INSTANCE_ID

# Wait for the instance to reach 2/2 status checks passed
aws ec2 wait instance-status-ok --instance-ids $PP_INSTANCE_ID

# Retrieve the public IP address of the PP instance
public_ip=$(aws ec2 describe-instances --instance-ids $PP_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "PP Public IP =  $public_ip "

# CODE DEPLOYMENT PROCESS : 

# SSH into the PP EC2 instance and execute commands
ssh -o StrictHostKeyChecking=no $EC2_USER@$public_ip << EOF
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


echo "Code Successfully Deployed in PP Server"
sleep 5

# ALB Check the status of instances in the target group for the traffic switch 
status=$(aws elbv2 describe-target-health --target-group-arn $PP_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
# Loop until all instances are healthy in the PP TG
while [ ! -z "$status" ]; do
    echo "Waiting for instances to become healthy..."
    sleep 5
    status=$(aws elbv2 describe-target-health --target-group-arn $PP_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
done

echo "All instances are healthy! in PP TG"
sleep 5 

# Modify the ALB listener to balance traffic between TG1 and TG2 (50/50)
aws elbv2 modify-listener \
  --listener-arn $ALB_LISTENER_ARN \
  --default-actions \
  "[{
      \"Type\": \"forward\",
      \"Order\": 1,
      \"ForwardConfig\": {
         \"TargetGroups\": [
           { \"TargetGroupArn\": \"$PROD_TG_ARN\",
             \"Weight\": 50 },
           { \"TargetGroupArn\": \"$PP_TG_ARN\",
             \"Weight\": 50 }
         ]
      }
  }]"


# Wait for 10 minutes (600 seconds) to check application integrity
# We can also use the jenkins to execute the next below command after the user intevention when application is working fine 
echo "Waiting for 20 min  for application validation..."
echo "PP & PROD is on 50/50 LOAD check application integrity "
sleep 600


## STEP: 2
# Modify the ALB listener to PROD-TG1 = 100
aws elbv2 modify-listener \
  --listener-arn $ALB_LISTENER_ARN \
  --default-actions \
  "[{
      \"Type\": \"forward\",
      \"Order\": 1,
      \"ForwardConfig\": {
         \"TargetGroups\": [
           { \"TargetGroupArn\": \"$PROD_TG_ARN\",
             \"Weight\": 0 },
           { \"TargetGroupArn\": \"$PP_TG_ARN\",
             \"Weight\": 100 }
         ]
      }
  }]"


echo " 100% traffic is on PP Server wait 5 min to check the payment crash while 100% LOAD on Server " 
sleep 300

