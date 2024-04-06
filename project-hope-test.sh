export TAG_DEPLOYED=11
########## PP ENVIRONMENT ############
# PP EC2 ID for deployment detup
export PP_INSTANCE_ID="ABCD"
## PP TG arn for healthy status check
export PP_TG_ARN="ABCD"

######### PROD ENVIRONMENT #################
# Set environment variables for AMI name and description
export AMI_NAME="ABCD" #need to change everytime
export AMI_DESCRIPTION="ABCD Description"
# Set environment variables for launch template
export LAUNCH_TEMPLATE_ID="ABCD"
# Replace YOUR_TARGET_GROUP_ARN with the ARN of your target group
export PROD_INSTANCE_ID="ABCD" ## FOR PROD SERVER ONLY
export ASG_NAME="ABCD"
export ALB_LISTENER_ARN=ABCD
export PROD_TG_ARN="ABCD"
export SSH_KEY=abc.pem
export EC2_USER=root


# Start the instance
aws ec2 start-instances --instance-ids $PP_INSTANCE_ID

# Wait for the instance to reach 2/2 status checks passed
aws ec2 wait instance-status-ok --instance-ids $PP_INSTANCE_ID

# Retrieve the public IP address of the instance
public_ip=$(aws ec2 describe-instances --instance-ids $PP_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "PP Public IP =  $public_ip "

# CODE DEPLOYMENT PROCESS : 
# NOTE : Copy the ENV from somewhere to current path && Zip the code of API in api.zip
# SSH into the PP EC2 instance and execute commands
sudo scp -o StrictHostKeyChecking=no -i $SSH_KEY ./ppindex.html $EC2_USER@$public_ip:/var/www/html/index.html
sudo ssh -o StrictHostKeyChecking=no -i $SSH_KEY $EC2_USER@$public_ip << EOF
  echo "Executing commands on the instance..."
  sudo apt update -y
  sudo apt install nginx -y
  curl http://localhost
EOF

echo "Code Successfully Deployed "
sleep 5


# ALB Check the status of instances in the target group for the traffic switch 
status=$(aws elbv2 describe-target-health --target-group-arn $PP_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
# Loop until all instances are healthy
while [ ! -z "$status" ]; do
    echo "Waiting for instances to become healthy..."
    sleep 5
    status=$(aws elbv2 describe-target-health --target-group-arn $PP_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
done

echo "All instances are healthy!"

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
echo "Waiting for 30 sec for application validation..."
echo "PP Deployed check application integrity "
sleep 10


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


## STEP : 3 
#################################### TAKE from new jenkins pipeline or use jenkins pipeline setup

# Wait for the instance to reach 2/2 status checks passed
aws ec2 wait instance-status-ok --instance-ids $PROD_INSTANCE_ID

# Retrieve the public IP address of the instance
public_ip_prod=$(aws ec2 describe-instances --instance-ids $PROD_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo $public_ip_prod

# CODE DEPLOYMENT PROCESS : 
# NOTE : Copy the ENV from somewhere to current path && Zip the code of API in api.zip
# SSH into the PP EC2 instance and execute commands
sudo scp -o StrictHostKeyChecking=no -i $SSH_KEY ./prodindex.html $EC2_USER@$public_ip_prod:/var/www/html/index.html
sudo ssh -o StrictHostKeyChecking=no -i $SSH_KEY $EC2_USER@$public_ip_prod << EOF
  echo "Executing commands on the instance..."
  sudo apt update -y
  sudo apt install nginx -y 
    curl http://localhost
EOF

echo "Code Successfully Deployed "
sleep 5

# Create an AMI of the instance
ami_id=$(aws ec2 create-image --instance-id $PROD_INSTANCE_ID --name "$AMI_NAME" --description "$AMI_DESCRIPTION" --no-reboot --output text)

# Wait for the AMI to be available
echo "Waiting for the AMI to be available..."
sleep 8
aws ec2 wait image-available --image-ids $ami_id
echo "AMI $ami_id is now available."
sleep 5

# Get the current version of the launch template
current_version=$(aws ec2 describe-launch-template-versions --launch-template-id $LAUNCH_TEMPLATE_ID --query 'LaunchTemplateVersions[0].VersionNumber' --output text)
echo $current_version


#Create a new version of the launch template by specifying the new AMI ID
launchTemplateVersions=$(aws ec2 create-launch-template-version --launch-template-id $LAUNCH_TEMPLATE_ID --source-version $current_version --launch-template-data "{ \"ImageId\": \"$ami_id\" }" --output text)

echo "New version of the launch template created with version number: $launchTemplateVersions"

# Set minimum, maximum, and desired capacity to 0 to delete the old ec2 instance 
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 0 --max-size 0 --desired-capacity 0

# Wait for 30 seconds to let it terminate
sleep 10

# Set minimum, maximum, and desired capacity to 2 to create a EC2 instance with new ami ID 
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 1 --max-size 1 --desired-capacity 1

# ALB Check the status of instances in the target group
status=$(aws elbv2 describe-target-health --target-group-arn $PROD_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)

# Loop until all instances are healthy
while [ ! -z "$status" ]; do
    echo "Waiting for instances to become healthy..."
    sleep 5
    status=$(aws elbv2 describe-target-health --target-group-arn $PROD_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
done

echo "All instances are healthy!"
sleep 5

# Modify the ALB listener to PROD_TG1 = 100
aws elbv2 modify-listener \
  --listener-arn $ALB_LISTENER_ARN \
  --default-actions \
  "[{
      \"Type\": \"forward\",
      \"Order\": 1,
      \"ForwardConfig\": {
         \"TargetGroups\": [
           { \"TargetGroupArn\": \"$PROD_TG_ARN\",
             \"Weight\": 100 },
           { \"TargetGroupArn\": \"$PP_TG_ARN\",
             \"Weight\": 0 }
         ]
      }
  }]"

# Stop the PP instance deployment is completed and working fine in PP as of now 
aws ec2 stop-instances --instance-ids $PP_INSTANCE_ID


### Deployed ###
echo " Deployed Successfully! "
echo " Deployed Successfully! "
echo " Deployed Successfully! "







