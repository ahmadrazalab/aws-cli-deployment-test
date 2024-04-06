>> HOW TO RUN 
```
./project-hope-test.sh 2> ./logs/error-$(date +"%Y-%m-%d")_$(date +"%H:%M:%S")
```

Here is the Deployment setup instructions:

---

# Deployment Setup

This readme provides step-by-step instructions for setting up and deploying your application.

## Prerequisites

- AWS CLI configured with necessary permissions.
- Jenkins pipeline setup.

## Deployment Steps

1. Set environment variables for AMI name and description:

   ```bash
   export AMI_NAME="MyInstanceAMINAME-as-tag"
   export AMI_DESCRIPTION="decription tag and info"
   ```

2. Set environment variables for launch template:

   ```bash
   export LAUNCH_TEMPLATE_ID="your-launch-template-id"
   ```

3. Replace `YOUR_TARGET_GROUP_ARN` with the ARN of your target group.

4. Wait for the instance to reach 2/2 status checks passed:

   ```bash
   aws ec2 wait instance-status-ok --instance-ids <INSTANCE_ID>
   ```

5. Retrieve the public IP address of the instance:

   ```bash
   public_ip=$(aws ec2 describe-instances --instance-ids <INSTANCE_ID> --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
   ```

6. Copy the ENV from somewhere to the current path and zip the code of API in `api.zip`.

7. SSH into the instance and execute commands:

   ```bash
   ssh -o StrictHostKeyChecking=no -P 33000 root@$public_ip << EOF
     echo "Executing commands on the instance..."
     cd /var/www/backend/
     rm -rf ./vendor ./composer.lock
     composer install
     chmod -R 777 ./storage
   EOF
   ```

8. Create an AMI of the instance:

   ```bash
   ami_id=$(aws ec2 create-image --instance-id <INSTANCE_ID> --name "$AMI_NAME" --description "$AMI_DESCRIPTION" --no-reboot --output text)
   ```

9. Wait for the AMI to be available:

   ```bash
   aws ec2 wait image-available --image-ids $ami_id
   ```

10. Get the current version of the launch template.

11. Create a new version of the launch template by specifying the new AMI ID.

12. Check the latest version of the launch template in ASG.

13. Set the desired capacity of the Auto Scaling Group to 0.

14. Wait for 1 minute.

15. Set the desired capacity of the Auto Scaling Group to 2.

16. Wait for 2 instances to become active.

17. Check the ALB health of EC2 instances and wait until all instances are healthy.

18. Modify the ALB listener to transfer traffic into TG1 for full production load.

19. Stop the PP instance as the deployment is completed and working fine in PP.

20. Deployment is completed successfully.

---

Note: Ensure to replace placeholders such as `<INSTANCE_ID>`, `<TARGET_GROUP_ARN>`, `<LISTENER_ARN>`, `<TARGET_GROUP_ARN_1>`, `<TARGET_GROUP_ARN_2>` with the actual values.

---

This readme provides a detailed guide to deploy your application using AWS services and CLI commands. If you encounter any issues during deployment, please refer to this readme or consult your deployment documentation.

For any further assistance, contact your system administrator or AWS support.

---

Feel free to customize the readme according to your specific deployment process and environment.