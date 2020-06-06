if  [ -n "$AWS_REGION" ] ;then
echo "AWS_REGION is $AWS_REGION" 
else
echo "AWS_REGION is not set this must be done before proceeding"
exit
fi
if  [ -n "$MASTER_ARN" ] ;then
echo "MASTER_ARN is $MASTER_ARN" 
else
echo "MASTER_ARN is not set this must be done before proceeding"
exit
fi
echo "Check my profile"
instid=`curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`
echo $instid
ip=`aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$instid" | jq .IamInstanceProfileAssociations[0].IamInstanceProfile.Arn | cut -f2 -d'/' | tr -d '"'`
echo $ip
if [ "$ip" != "eksworkshop-admin" ] ; then
echo "Could not find Instance profile eksworkshop-admin DO NOT PROCEED exiting"
exit
else
echo "OK Found Instance profile eksworkshop-admin"
fi
aws sts get-caller-identity --query Arn | grep eksworkshop-admin -q && echo "IAM role valid eksworkshop-admin OK to proceed" || echo "IAM role NOT validi DO NOT PROCEED"
