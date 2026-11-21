"""Start the EC2 standby when the primary-unhealthy alarm fires.

This only powers the VM on. Moving traffic is a deliberate operator action
(see scripts/failover.sh) because ECS and EC2 must never both write to the
shared RDS/EFS at the same time.
"""

import json
import os

import boto3

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

INSTANCE_ID = os.environ["INSTANCE_ID"]
TOPIC = os.environ["SNS_TOPIC_ARN"]
ALARM = os.environ["ALARM_NAME"]


def handler(event, context):
    state = ec2.describe_instances(InstanceIds=[INSTANCE_ID])["Reservations"][0]["Instances"][0]["State"]["Name"]
    print(json.dumps({"instance": INSTANCE_ID, "state": state, "alarm": ALARM}))

    if state in ("stopped",):
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
        action = "started"
    elif state == "stopping":
        # Cannot start while stopping; raise so Lambda's async retry tries again
        raise RuntimeError("Standby is stopping; retrying")
    else:
        action = f"left as-is ({state})"

    sns.publish(
        TopicArn=TOPIC,
        Subject=f"[Mealie] Standby EC2 {action}"[:100],
        Message=(
            f"Alarm {ALARM} entered ALARM. Standby instance {INSTANCE_ID} was {action}.\n\n"
            "Traffic has NOT been moved. To fail over, run:\n"
            "  terraform/modules/failover/scripts/failover.sh cutover\n"
        ),
    )
    return {"instance": INSTANCE_ID, "action": action}
