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


#### DEPLOYMENT PROCESS ####### 
# Create an AMI of the instance
ami_id=$(aws ec2 create-image --instance-id $PROD_INSTANCE_ID --name "BUILD-NO-$BUILD_NUMBER AMI-NAME-$AMI_NAME" --description "BUILD-NO-$BUILD_NUMBER AMI-NAME-$AMI_NAME" --no-reboot --output text)
echo "$ami_id"
# Wait for the AMI to be available
echo "Waiting for the AMI to be available..."
sleep 8
aws ec2 wait image-available --image-ids $ami_id
echo "AMI = $ami_id is now available."
sleep 3


# Create a new Version of Launch Template with new AMI ID 
aws ec2 create-launch-template-version \
    --launch-template-name $PROD_LT_NAME \
    --source-version 1 \
    --launch-template-data "{
        \"ImageId\": \"$ami_id\"
    }"

aws ec2 describe-launch-template-versions \
    --launch-template-name $PROD_LT_NAME


# Set minimum, maximum, and desired capacity to 0 to delete the old ec2 instance 
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 0 --max-size 0 --desired-capacity 0

# Wait for 30 seconds to let it terminate
echo " ASG terminating old instance in PP-LT " 
sleep 30

# Set minimum, maximum, and desired capacity to 2 to create a EC2 instance with new ami ID 
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 2 --max-size 5 --desired-capacity 2
# Wait for 30 seconds to let it create new ec2
echo " ASG creating new EC2 instance in from AMI = $ami_id " 
sleep 30


# ALB Check the status of instances in the target group
status=$(aws elbv2 describe-target-health --target-group-arn $PROD_TG_ARN --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`].TargetHealth.State' --output text)

echo " THE STATUS OF INSTNACE IS = $status "

# Loop until all instances are healthy
while [ ! -z "$status" ]; do
    echo "Waiting for instances to become healthy...# $status"
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
echo "100% load in PROD instance ID = $PROD_INSTANCE_ID & PROD instance IP = $public_ip_prod"
echo " Wait 5 min before stopping PP instance"
sleep 300


# Stop the PP instance deployment is completed and working fine in PP as of now 
aws ec2 stop-instances --instance-ids $PP_INSTANCE_ID
echo " stopping PP instance = $PP_INSTANCE_ID "

### Deployed ###
echo " Deployed Successfully! "
echo " Deployed Successfully! "
echo " Deployed Successfully! "
