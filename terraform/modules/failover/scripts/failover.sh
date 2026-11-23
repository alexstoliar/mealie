#!/usr/bin/env bash
# Operator-approved failover between ECS (primary) and EC2 (standby).
#
#   failover.sh status     show instance state, target health, active listener target
#   failover.sh cutover    stop ECS writes -> start Mealie on EC2 -> verify -> switch ALB
#   failover.sh failback   restore ECS -> verify -> switch ALB -> stop Mealie on EC2
#
# Run from terraform/ (needs `terraform init` done) with AWS credentials.
set -euo pipefail

cd "$(dirname "$0")/../../.."
tf() { terraform output -raw "$1"; }

REGION=$(tf aws_region)
CLUSTER=$(tf ecs_cluster_name)
SERVICE=$(tf ecs_service_name)
INSTANCE=$(tf standby_instance_id)
DOC=$(tf standby_ssm_document)
EC2_TG=$(tf standby_target_group_arn)
ECS_TG=$(tf primary_target_group_arn)
LISTENER=$(tf alb_listener_arn)
export AWS_DEFAULT_REGION=$REGION
export AWS_PAGER=""  # AWS CLI v2 would otherwise open `less` on long output and hang the script

confirm() { read -r -p "$1 [type 'yes']: " a; [ "$a" = "yes" ] || { echo "Aborted"; exit 1; }; }

active_tg() {
  aws elbv2 describe-listeners --listener-arns "$LISTENER" \
    --query 'Listeners[0].DefaultActions[0].TargetGroupArn' --output text
}

tg_healthy() { # $1 = tg arn
  aws elbv2 describe-target-health --target-group-arn "$1" \
    --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text
}

wait_healthy() {
  echo "Waiting for $1 targets to become healthy..."
  for _ in $(seq 1 40); do
    [ "$(tg_healthy "$1")" -ge 1 ] && { echo "healthy"; return 0; }
    sleep 15
  done
  echo "Target group never became healthy" >&2; return 1
}

ssm_run() { # $1 = start|stop
  local id
  id=$(aws ssm send-command --document-name "$DOC" --instance-ids "$INSTANCE" \
    --parameters "action=$1" --query 'Command.CommandId' --output text)
  # The built-in waiter gives up after ~100s; first start (docker install + image pull) takes longer.
  local st=""
  for _ in $(seq 1 120); do  # up to 10 min
    st=$(aws ssm get-command-invocation --command-id "$id" --instance-id "$INSTANCE" \
      --query Status --output text 2>/dev/null || echo Pending)
    case "$st" in Pending|InProgress|Delayed) sleep 5 ;; *) break ;; esac
  done
  aws ssm get-command-invocation --command-id "$id" --instance-id "$INSTANCE" \
    --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
  [ "$(aws ssm get-command-invocation --command-id "$id" --instance-id "$INSTANCE" --query Status --output text)" = "Success" ]
}

set_listener() {
  aws elbv2 modify-listener --listener-arn "$LISTENER" \
    --default-actions "Type=forward,TargetGroupArn=$1" >/dev/null
}

ensure_instance() {
  local state
  state=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].State.Name' --output text)
  if [ "$state" != "running" ]; then
    echo "Starting standby instance ($state)..."
    aws ec2 start-instances --instance-ids "$INSTANCE" >/dev/null
    aws ec2 wait instance-running --instance-ids "$INSTANCE"
  fi
  echo "Waiting for SSM agent..."
  for _ in $(seq 1 30); do
    [ "$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE" \
      --query 'length(InstanceInformationList)' --output text)" -ge 1 ] && return 0
    sleep 10
  done
  echo "SSM agent not online" >&2; return 1
}

case "${1:-}" in
  status)
    echo "Instance:        $(aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].State.Name' --output text)"
    echo "ECS healthy:     $(tg_healthy "$ECS_TG")"
    echo "EC2 healthy:     $(tg_healthy "$EC2_TG")"
    [ "$(active_tg)" = "$EC2_TG" ] && echo "Listener target: EC2 standby" || echo "Listener target: ECS primary"
    ;;

  cutover)
    [ "$(active_tg)" = "$EC2_TG" ] && { echo "Already on EC2"; exit 0; }
    confirm "Stop ECS (primary writes) and move traffic to the EC2 standby?"
    ensure_instance
    # One active writer: stop ECS BEFORE starting Mealie on EC2 (shared RDS + EFS)
    echo "Scaling ECS service to 0..."
    aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 0 >/dev/null
    aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
    ssm_run start
    wait_healthy "$EC2_TG"
    set_listener "$EC2_TG"
    echo "Cutover complete: ALB now serves the EC2 standby."
    ;;

  failback)
    [ "$(active_tg)" = "$ECS_TG" ] && { echo "Already on ECS"; exit 0; }
    confirm "Stop Mealie on EC2 and move traffic back to ECS?"
    ssm_run stop
    aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 1 >/dev/null
    aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
    wait_healthy "$ECS_TG"
    set_listener "$ECS_TG"
    read -r -p "Stop the standby instance too? [y/N]: " a
    [ "$a" = "y" ] && aws ec2 stop-instances --instance-ids "$INSTANCE" >/dev/null
    echo "Failback complete: ALB now serves ECS."
    ;;

  *) echo "Usage: $0 {status|cutover|failback}" >&2; exit 2 ;;
esac
