#!/bin/bash -e

# Install & configure awslogs
apt -y install python
curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
python ./awslogs-agent-setup.py --region eu-west-1 -n true -c /awslogs.conf
rm /awslogs.conf