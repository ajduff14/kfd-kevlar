#/bin/bash

regions=$(aws ec2 describe-regions --output text --query 'Regions[*].RegionName')
for region in $regions; do
    (
    echo $region $(aws ec2 describe-images --owners 099720109477 --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server*' 'Name=state,Values=available' --output json | jq -r '.Images | 
sort_by(.CreationDate) | last(.[]).ImageId')
    )
done