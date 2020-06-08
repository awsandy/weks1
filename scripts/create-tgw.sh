nc=`aws eks list-clusters | jq '.clusters | length'`
if [ $nc == 1 ] ; then
export CLUSTER=`aws eks list-clusters | jq '.clusters[0]' | tr -d '"'`
echo "EKS Cluster = $CLUSTER"
else
echo "Please set the environment variable CLUSTER"
exit
fi 

tgcr=`aws ec2 create-transit-gateway --description EKSTGW \
--options=AmazonSideAsn=64616,AutoAcceptSharedAttachments=enable`
echo "get the transit gateway id"
tid=`echo $tgcr | jq ".TransitGateway.TransitGatewayId" | tr -d '"'`
echo "Transit gateway ID = $tid"
tgstate=`aws ec2 describe-transit-gateways --transit-gateway-id $tid --query "TransitGateways[0].State" | tr -d '"'`

while [ "$tgstate" != "available" ]; do
echo "Waiting for TGW to become available, currently = $tgstate"
sleep 10
tgstate=`aws ec2 describe-transit-gateways --transit-gateway-id $tid --query "TransitGateways[0].State" | tr -d '"'`
done


echo "get the default vpcid"
did=`aws ec2 describe-vpcs | jq '.Vpcs[] | select(.IsDefault==true).VpcId' | tr -d '"'`
echo "Default VPC Id = $did"
dcidr=`aws ec2 describe-vpcs | jq '.Vpcs[] | select(.IsDefault==true).CidrBlock' | tr -d '"'`
echo "Default VPC CIDR = $dcidr"
drtbid=`aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$did" --query "RouteTables[?starts_with(to_string(Associations[0].Main),'true')] | [0].Associations[0].RouteTableId" | tr -d '"'`
echo "Default VPC Routing table Id = $drtbid"
#aws ec2 describe-vpcs | jq '.Vpcs[] |  select(.Tags | indices({Key:"Name", Value:"DefaultVPC"}) != [])' | jq .VpcId
# aws ec2 describe-vpcs | jq '.Vpcs[] |  select(.Tags[].Value | contains("DefaultVPC")).VpcId'

echo "get the 3x subnet id's from the Default vpc for TGW attachment"
subs=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$did"`
sub0=`echo $subs | jq .Subnets[0].SubnetId | tr -d '"'`
sub1=`echo $subs | jq .Subnets[1].SubnetId | tr -d '"'`
sub2=`echo $subs | jq .Subnets[2].SubnetId | tr -d '"'`
echo "Attach the Default VPC's 3x subnets to our transit gateway"
tgast=`aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $tid \
    --vpc-id $did \
    --subnet-ids $sub0 $sub1 $sub2`
echo $tgast | jq .
tgwatt=`echo $tgast | jq '.TransitGatewayVpcAttachment.TransitGatewayAttachmentId' | tr -d '"'`
tgstate=`aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $tgwatt --query "TransitGatewayVpcAttachments[0].State" | tr -d '"'`
#echo "tgstate=$tgstate"
while [ "$tgstate" != "available" ]; do
echo "Waiting for TGW attachment to become available, currently = $tgstate"
sleep 10
tgstate=`aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $tgwatt --query "TransitGatewayVpcAttachments[0].State" | tr -d '"'`
done


echo "Get the EKS VPC id"
comm=`printf "aws ec2 describe-vpcs | jq '.Vpcs[] |  select(try .Tags[].Value==\"%s\").VpcId'" $CLUSTER`
cid=`eval $comm | head -1 | tr -d '"'`
echo "EKS VPC Id = $cid"

echo "Get the EKS VPC CIDR"
comm=`printf "aws ec2 describe-vpcs | jq '.Vpcs[] |  select(try .Tags[].Value==\"%s\").CidrBlock'" $CLUSTER`
ccidr=`eval $comm | head -1 | tr -d '"'`
echo "EKS VPC Primary CIDR = $ccidr"

sub0=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$cid" --query "Subnets[?starts_with(to_string(MapPublicIpOnLaunch),'false')]|[0].SubnetId" | tr -d '"'`
echo "EKS VPC Private subnet 1 = $sub0"
sub1=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$cid" --query "Subnets[?starts_with(to_string(MapPublicIpOnLaunch),'false')]|[1].SubnetId" | tr -d '"'`
echo "EKS VPC Private subnet 2 = $sub1"
sub2=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$cid" --query "Subnets[?starts_with(to_string(MapPublicIpOnLaunch),'false')]|[2].SubnetId" | tr -d '"'`
echo "EKS VPC Private subnet 3 = $sub2"
# get the route tables
crtb0=`aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$cid" --query "RouteTables[?starts_with(to_string(Associations[0].SubnetId),'$sub0')] | [0].Associations[0].RouteTableId" | tr -d '"'`
echo "Routing Table for subnet $sub0 = $crtb0"
crtb1=`aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$cid" --query "RouteTables[?starts_with(to_string(Associations[0].SubnetId),'$sub1')] | [0].Associations[0].RouteTableId" | tr -d '"'`
echo "Routing Table for subnet $sub1 = $crtb1"
crtb2=`aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$cid" --query "RouteTables[?starts_with(to_string(Associations[0].SubnetId),'$sub2')] | [0].Associations[0].RouteTableId" | tr -d '"'`
echo "Routing Table for subnet $sub2 = $crtb2"


echo "Attach the Clusters VPC's 3x private subnets to our transit gateway"
tgast=`aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $tid \
    --vpc-id $cid \
    --subnet-ids $sub0 $sub1 $sub2`

echo $tgast | jq .
tgwatt=`echo $tgast | jq '.TransitGatewayVpcAttachment.TransitGatewayAttachmentId' | tr -d '"'`
tgstate=`aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $tgwatt --query "TransitGatewayVpcAttachments[0].State" | tr -d '"'`
#echo "tgstate=$tgstate"
while [ "$tgstate" != "available" ]; do
echo "Waiting for TGW attachment to become available, currently = $tgstate"
sleep 10
tgstate=`aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $tgwatt --query "TransitGatewayVpcAttachments[0].State" | tr -d '"'`
done


echo "Routing tables - add route from default to cluster subnet via TGW"
echo $drtbid $ccidr $tid
aws ec2 create-route --route-table-id $drtbid --destination-cidr-block $ccidr --transit-gateway-id $tid

echo "Routing tables - add route from cluster 3x private subnets to default via TGW"
echo $crtb0 $dcidr $tid
aws ec2 create-route --route-table-id $crtb0 --destination-cidr-block $dcidr --transit-gateway-id $tid
echo $crtb1 $dcidr $tid
aws ec2 create-route --route-table-id $crtb1 --destination-cidr-block $dcidr --transit-gateway-id $tid
echo $crtb2 $dcidr $tid
aws ec2 create-route --route-table-id $crtb2 --destination-cidr-block $dcidr --transit-gateway-id $tid

echo "Find the Security Group Ids"

clsg=`aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.clusterSecurityGroupId | tr -d '"'`
echo "Cluster Security Group = $clsg"
clra=`aws ec2 describe-security-groups --query "SecurityGroups[?starts_with(GroupName,'eks-remoteAccess')]|[0].GroupId" | tr -d '"'`
echo "EKS remote ssh access Security Group = $clra"
isg=`curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/security-groups`
idesg=`aws ec2 describe-security-groups --query "SecurityGroups[?starts_with(GroupName,'${isg}')]|[0].GroupId" | tr -d '"'`
echo "Cloud9 Security Group = $idesg"
# add various SG rules
echo "Add access to EKS API for cloud9 SG"
aws ec2 authorize-security-group-ingress \
    --group-id $clsg \
    --protocol tcp \
    --port 443 \
    --cidr $dcidr
#echo "Add remote access to worker nodes for cloud9 SG"
#aws ec2 authorize-security-group-ingress \
#    --group-id $clra \
#    --protocol tcp \
#    --port 22 \
#    --destination-cidr-block $dcidr

# check access
echo "wait 60s to settle before test"
sleep 60
echo "check access"
testip=`kubectl get nodes -o json | jq '.items[0].status.addresses[] | select(.type=="Hostname").address' | tr -d '"'`
nmap $testip -Pn -p 22
echo "If the above shows port 22 open you can switch to EKS private API server endpoint access"




