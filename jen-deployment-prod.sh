#############################################################3 TAKE from new jenkins pipeline or use jenkins pipeline setup

# Set environment variables for AMI name and description
export AMI_NAME="MyInstanceAMINAME-as-tag"
export AMI_DESCRIPTION="decription tag and info"
# Set environment variables for launch template
export LAUNCH_TEMPLATE_ID="your-launch-template-id"
# export AMI_ID="your-ami-id"
# Replace YOUR_TARGET_GROUP_ARN with the ARN of your target group
export TARGET_GROUP_ARN="YOUR_TARGET_GROUP_ARN"


# Wait for the instance to reach 2/2 status checks passed
aws ec2 wait instance-status-ok --instance-ids <INSTANCE_ID>

# Retrieve the public IP address of the instance
public_ip=$(aws ec2 describe-instances --instance-ids <INSTANCE_ID> --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

# Copy the ENV from somewhere to current path && Zip the code of API in api.zip










# SSH into the PP EC2 instance and execute commands
ssh -o StrictHostKeyChecking=no -P 33000 root@$public_ip << EOF
  echo "Executing commands on the instance..."
  cd /var/www/backend/
  rm -rf ./vendor ./composer.lock
  composer install
  chmod -R 777 ./storage
EOF

# Create an AMI of the instance
ami_id=$(aws ec2 create-image --instance-id <INSTANCE_ID> --name "$AMI_NAME" --description "$AMI_DESCRIPTION" --no-reboot --output text)

# Wait for the AMI to be available
echo "Waiting for the AMI to be available..."
aws ec2 wait image-available --image-ids $ami_id
echo "AMI $ami_id is now available."

# Get the current version of the launch template
current_version=$(aws ec2 describe-launch-template-versions --launch-template-id $LAUNCH_TEMPLATE_ID --query 'LaunchTemplateVersions[0].VersionNumber' --output text)

###
### USER interaction #####################################################################################################
###
# Create a new version of the launch template by specifying the new AMI ID
launchTemplateVersions=$(aws ec2 create-launch-template-version --launch-template-id $LAUNCH_TEMPLATE_ID --source-version $current_version --launch-template-data "{ \"ImageId\": \"$ami_id\" }" --output text)

echo "New version of the launch template created with version number: $launchTemplateVersions"


### Check the latest version of launch temaplet in ASG 
#!/bin/bash

# Set environment variables
# export ASG_NAME="your-auto-scaling-group-name"

# # Get the launch template ID used by the Auto Scaling Group
# launch_template_id=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query "AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId" --output text)

# # Get the latest version of the launch template
# latest_version=$(aws ec2 describe-launch-template-versions --launch-template-id $launch_template_id --query 'LaunchTemplateVersions[-1].VersionNumber' --output text)

# echo "The Auto Scaling Group $ASG_NAME is currently using launch template version $latest_version"


# Set the desired capacity of the Auto Scaling Group to 0
aws autoscaling set-desired-capacity --auto-scaling-group-name YOUR_ASG_NAME --desired-capacity 0

# Wait for 1 minutes
# sleep 60

# Function to get the number of active instances
get_active_instance_count() {
    aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'].length(@)"
}

# Check the current number of active instances
active_instance_count=$(get_active_instance_count)

# Loop until the number of active instances decreases to 1
while [ "$active_instance_count" -gt 1 ]; do
    echo "Waiting for active instances to decrease to 1..."
    sleep 10
    active_instance_count=$(get_active_instance_count)
done

echo "There is only 1 active instance now."

# Set the desired capacity of the Auto Scaling Group to 2
aws autoscaling set-desired-capacity --auto-scaling-group-name YOUR_ASG_NAME --desired-capacity 2

# Function to get the number of active instances
get_active_instance_count() {
    aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN \
    --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'].length(@)"
}

# Check the current number of active instances
active_instance_count=$(get_active_instance_count)

# Loop until the number of active instances increses to 2
while [ "$active_instance_count" -gt 2 ]; do
    echo "Waiting for active instances to increses to 2..."
    sleep 10
    active_instance_count=$(get_active_instance_count)
done

echo "There is  2 active instance now. Created by ASG "


# ALB health of EC2 Check 2/2 
# Check the status of instances in the target group
status=$(aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)

# Loop until all instances are healthy
while [ ! -z "$status" ]; do
    echo "Waiting for instances to become healthy..."
    sleep 10
    status=$(aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)
done

echo "All instances are healthy!"


# Modify the ALB listener to transfer the traffic into TG1 for full production load 
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --default-actions \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_1>,Weight=100 \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_2>,Weight=0


## Stop the PP instance deployment is completed and working fine in PP as of now 
aws ec2 stop-instances --instance-ids <INSTANCE_ID>



### Deployed ###
echo " Deployed Successfully "






