# Start the instance
aws ec2 start-instances --instance-ids <INSTANCE_ID>

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


# Modify the ALB listener to balance traffic between TG1 and TG2 (50/50)
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --default-actions \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_1>,Weight=50 \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_2>,Weight=50

# Wait for 20 minutes (1200 seconds) to check application integrity
# We can also use the jenkins to execute the next below command after the user intevention when application is working fine 
echo "Waiting for 20 minutes for application validation..."
sleep 1200

# Modify the ALB listener to transfer 100% load to TG2 and TG1 with 0% load
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --default-actions \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_2>,Weight=100 \
    Type=forward,TargetGroupArn=<TARGET_GROUP_ARN_1>,Weight=0


################################ PP Deploy is completed ############################################ >> PROCEED TO PROD API 