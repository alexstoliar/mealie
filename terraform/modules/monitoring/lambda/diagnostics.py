"""Collect diagnostics when the ALB "unhealthy targets" alarm fires and store a report in S3."""

import json
import os
import time
from datetime import UTC, datetime, timedelta

import boto3

REGION = os.environ["AWS_REGION"]
BUCKET = os.environ["REPORT_BUCKET"]
CLUSTER = os.environ["CLUSTER_NAME"]
SERVICE = os.environ["SERVICE_NAME"]
TARGET_GROUP_ARN = os.environ["TARGET_GROUP_ARN"]
LOG_GROUP = os.environ["LOG_GROUP_NAME"]
DB_INSTANCE_ID = os.environ["DB_INSTANCE_ID"]
EFS_ID = os.environ["EFS_ID"]

elbv2 = boto3.client("elbv2")
ecs = boto3.client("ecs")
logs = boto3.client("logs")
rds = boto3.client("rds")
efs = boto3.client("efs")
cw = boto3.client("cloudwatch")
s3 = boto3.client("s3")


def safe(fn):
    """Run a collector; a failure in one section must not lose the whole report."""
    try:
        return fn()
    except Exception as exc:  # noqa: BLE001
        return {"error": f"{type(exc).__name__}: {exc}"}


def target_health():
    out = elbv2.describe_target_health(TargetGroupArn=TARGET_GROUP_ARN)
    return [
        {
            "target": d["Target"]["Id"],
            "port": d["Target"].get("Port"),
            "state": d["TargetHealth"]["State"],
            "reason": d["TargetHealth"].get("Reason"),
            "description": d["TargetHealth"].get("Description"),
        }
        for d in out["TargetHealthDescriptions"]
    ]


def ecs_service():
    svc = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])["services"][0]
    return {
        "status": svc["status"],
        "desired": svc["desiredCount"],
        "running": svc["runningCount"],
        "pending": svc["pendingCount"],
        "task_definition": svc["taskDefinition"],
        "deployments": [
            {
                "status": d["status"],
                "rollout_state": d.get("rolloutState"),
                "rollout_reason": d.get("rolloutStateReason"),
                "running": d["runningCount"],
                "desired": d["desiredCount"],
                "failed_tasks": d.get("failedTasks"),
            }
            for d in svc["deployments"]
        ],
        "recent_events": [
            {"at": e["createdAt"].isoformat(), "message": e["message"]} for e in svc["events"][:15]
        ],
    }


def ecs_tasks():
    result = {}
    for status in ("RUNNING", "STOPPED"):
        arns = ecs.list_tasks(cluster=CLUSTER, serviceName=SERVICE, desiredStatus=status, maxResults=10)["taskArns"]
        if not arns:
            result[status.lower()] = []
            continue
        tasks = ecs.describe_tasks(cluster=CLUSTER, tasks=arns)["tasks"]
        result[status.lower()] = [
            {
                "task": t["taskArn"].split("/")[-1],
                "last_status": t["lastStatus"],
                "health": t.get("healthStatus"),
                "started_at": t["startedAt"].isoformat() if t.get("startedAt") else None,
                "stopped_at": t["stoppedAt"].isoformat() if t.get("stoppedAt") else None,
                "stop_code": t.get("stopCode"),
                "stopped_reason": t.get("stoppedReason"),
                "containers": [
                    {
                        "name": c["name"],
                        "status": c["lastStatus"],
                        "exit_code": c.get("exitCode"),
                        "reason": c.get("reason"),
                    }
                    for c in t["containers"]
                ],
            }
            for t in tasks
        ]
    return result


def app_logs():
    start = int((time.time() - 30 * 60) * 1000)
    errors = logs.filter_log_events(
        logGroupName=LOG_GROUP,
        startTime=start,
        filterPattern="?ERROR ?Error ?Exception ?Traceback ?CRITICAL ?FATAL",
        limit=50,
    )["events"]
    recent = logs.filter_log_events(logGroupName=LOG_GROUP, startTime=start, limit=50)["events"]
    fmt = lambda evs: [  # noqa: E731
        {"at": datetime.fromtimestamp(e["timestamp"] / 1000, UTC).isoformat(), "message": e["message"][:1000]}
        for e in evs
    ]
    return {"errors_last_30m": fmt(errors), "latest_lines": fmt(recent[-30:])}


def rds_status():
    db = rds.describe_db_instances(DBInstanceIdentifier=DB_INSTANCE_ID)["DBInstances"][0]
    events = rds.describe_events(SourceIdentifier=DB_INSTANCE_ID, SourceType="db-instance", Duration=180)["Events"]
    return {
        "status": db["DBInstanceStatus"],
        "class": db["DBInstanceClass"],
        "multi_az": db["MultiAZ"],
        "allocated_storage_gb": db["AllocatedStorage"],
        "pending_modifications": db.get("PendingModifiedValues"),
        "recent_events": [{"at": e["Date"].isoformat(), "message": e["Message"]} for e in events[:15]],
    }


def efs_status():
    fs = efs.describe_file_systems(FileSystemId=EFS_ID)["FileSystems"][0]
    targets = efs.describe_mount_targets(FileSystemId=EFS_ID)["MountTargets"]
    return {
        "state": fs["LifeCycleState"],
        "size_bytes": fs["SizeInBytes"]["Value"],
        "mount_targets": [{"az": t["AvailabilityZoneName"], "state": t["LifeCycleState"]} for t in targets],
    }


def key_metrics():
    now = datetime.now(UTC)
    queries = [
        ("ecs_cpu", "AWS/ECS", "CPUUtilization", [("ClusterName", CLUSTER), ("ServiceName", SERVICE)]),
        ("ecs_memory", "AWS/ECS", "MemoryUtilization", [("ClusterName", CLUSTER), ("ServiceName", SERVICE)]),
        ("rds_cpu", "AWS/RDS", "CPUUtilization", [("DBInstanceIdentifier", DB_INSTANCE_ID)]),
        ("rds_connections", "AWS/RDS", "DatabaseConnections", [("DBInstanceIdentifier", DB_INSTANCE_ID)]),
        ("rds_free_memory", "AWS/RDS", "FreeableMemory", [("DBInstanceIdentifier", DB_INSTANCE_ID)]),
    ]
    data = cw.get_metric_data(
        MetricDataQueries=[
            {
                "Id": qid,
                "MetricStat": {
                    "Metric": {
                        "Namespace": ns,
                        "MetricName": name,
                        "Dimensions": [{"Name": k, "Value": v} for k, v in dims],
                    },
                    "Period": 300,
                    "Stat": "Average",
                },
            }
            for qid, ns, name, dims in queries
        ],
        StartTime=now - timedelta(minutes=30),
        EndTime=now,
    )["MetricDataResults"]
    return {r["Id"]: [round(v, 2) for v in r["Values"]] for r in data}


def to_markdown(report):
    lines = [
        f"# Diagnostic report - {report['alarm']['name']}",
        f"Generated: {report['generated_at']}",
        f"Alarm state: {report['alarm']['state']} ({report['alarm']['reason']})",
        "",
    ]
    for section, body in report["diagnostics"].items():
        lines += [f"## {section}", "```json", json.dumps(body, indent=2, default=str), "```", ""]
    return "\n".join(lines)


def handler(event, context):
    detail = event.get("detail", {})
    now = datetime.now(UTC)
    report = {
        "generated_at": now.isoformat(),
        "alarm": {
            "name": detail.get("alarmName"),
            "state": detail.get("state", {}).get("value"),
            "reason": detail.get("state", {}).get("reason"),
        },
        "diagnostics": {
            "alb_target_health": safe(target_health),
            "ecs_service": safe(ecs_service),
            "ecs_tasks": safe(ecs_tasks),
            "application_logs": safe(app_logs),
            "rds": safe(rds_status),
            "efs": safe(efs_status),
            "metrics_last_30m": safe(key_metrics),
        },
    }
    prefix = f"diagnostics/{now:%Y/%m/%d}/{now:%H%M%S}"
    s3.put_object(
        Bucket=BUCKET, Key=f"{prefix}.json", Body=json.dumps(report, indent=2, default=str), ContentType="application/json"
    )
    s3.put_object(Bucket=BUCKET, Key=f"{prefix}.md", Body=to_markdown(report), ContentType="text/markdown")
    return {"report": f"s3://{BUCKET}/{prefix}.json"}
