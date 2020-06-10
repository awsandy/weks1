eksctl create iamidentitymapping --cluster eksworkshop-eksctl --arn arn:aws:iam::${ACCOUNT_ID}:role/k8sDev --username dev-user
eksctl create iamidentitymapping --cluster eksworkshop-eksctl --arn arn:aws:iam::${ACCOUNT_ID}:role/k8sInteg --username integ-user
eksctl create iamidentitymapping --cluster eksworkshop-eksctl --arn arn:aws:iam::${ACCOUNT_ID}:role/k8sAdmin --username admin --group system:masters
kubectl get cm -n kube-system aws-auth -o yaml
eksctl get iamidentitymapping --cluster eksworkshop-eksctl
