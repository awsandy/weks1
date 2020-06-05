#kubectl get configmap -n kube-system aws-auth -o yaml > /tmp/aws-auth.yaml
#cat /tmp/aws-auth.yaml
echo "Check my profile"
instid=`curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`
echo $instid
ip=`aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$instid" | jq .IamInstanceProfileAssociations[0].IamInstanceProfile.Arn | cut -f2 -d'/' | tr -d '"'`
echo $ip
if [ "$ip" != "eksworkshop-admin" ] ; then
echo "Could not find Instance profile eksworkshop-admin exiting"
exit
else
echo "OK Found Instance profile eksworkshop-admin"
fi
aws sts get-caller-identity --query Arn | grep eksworkshop-admin -q && echo "IAM role valid - eksworkshop-admin" || echo "IAM role NOT valid"
