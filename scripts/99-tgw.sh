nc=`aws eks list-clusters | jq '.clusters | length'`
if [ $nc == 1 ] ; then
export CLUSTER=`aws eks list-clusters | jq '.clusters[0]' | tr -d '"'`
echo "EKS Cluster = $CLUSTER"
else
echo "Please set the environment variable CLUSTER"
exit
fi 

echo "get the transit gateway id"
tid=`aws ec2 describe-transit-gateways --query "TransitGateways[?Description=='EKSTGW']|[?contains(State,'available')]".TransitGatewayId | jq .[] | tr -d '"'`
if [ "$tid" == "" ];then
echo "no avilable TGW exiting"
exit
fi
echo "Transit gateway ID = $tid"
echo "get the default vpcid"
did=`aws ec2 describe-vpcs | jq '.Vpcs[] | select(.IsDefault==true).VpcId' | tr -d '"'`
echo "Default VPC Id = $did"
dcidr=`aws ec2 describe-vpcs | jq '.Vpcs[] | select(.IsDefault==true).CidrBlock' | tr -d '"'`
echo "Default VPC CIDR = $dcidr"
drtbid=`aws ec2 describe-route-tables --filter "Name=vpc-id,Values=$did" --query "RouteTables[?starts_with(to_string(Associations[0].Main),'true')] | [0].Associations[0].RouteTableId" | tr -d '"'`
echo "Default VPC Routing table Id = $drtbid"

echo "get the 3x subnet id's from the Default vpc for TGW attachment"
subs=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$did"`
sub0=`echo $subs | jq .Subnets[0].SubnetId | tr -d '"'`
sub1=`echo $subs | jq .Subnets[1].SubnetId | tr -d '"'`
sub2=`echo $subs | jq .Subnets[2].SubnetId | tr -d '"'`
echo "Attach the Default VPC's 3x subnets to our transit gateway"

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

aws ec2 delete-route --route-table-id $drtbid --destination-cidr-block $ccidr

aws ec2 delete-route --route-table-id $crtb0 --destination-cidr-block $dcidr 
aws ec2 delete-route --route-table-id $crtb1 --destination-cidr-block $dcidr
aws ec2 delete-route --route-table-id $crtb2 --destination-cidr-block $dcidr

echo "Find the Security Group Ids"

clsg=`aws eks describe-cluster --name $CLUSTER --query cluster.resourcesVpcConfig.clusterSecurityGroupId | tr -d '"'`
clra=`aws ec2 describe-security-groups --query "SecurityGroups[?starts_with(GroupName,'eks-remoteAccess')]|[0].GroupId" | tr -d '"'`
idesg=`aws ec2 describe-security-groups --query "SecurityGroups[?starts_with(GroupName,'aws-cloud9-eks')]|[0].GroupId" | tr -d '"'`
# remove various SG rules
echo "remove access to EKS API for cloud9 SG"
aws ec2 revoke-security-group-ingress \
    --group-id $clsg \
    --protocol tcp \
    --port 443 \
    --cidr $dcidr
echo "Remove remote access to worker nodes for cloud9 SG"
aws ec2 revoke-security-group-ingress \
    --group-id $clra \
    --protocol tcp \
    --port 22 \
    --cidr $dcidr

echo "Remove TGW Associations"
tga0=`aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$tid"  --query "TransitGatewayAttachments[0].TransitGatewayAttachmentId" | tr -d '"'`
tga1=`aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$tid"  --query "TransitGatewayAttachments[1].TransitGatewayAttachmentId" | tr -d '"'`

aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $tga0
aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $tga1 
echo "Wait 90s for detachment..."
sleep 90
echo "Remove TGW"
aws ec2 delete-transit-gateway --transit-gateway-id $tid

