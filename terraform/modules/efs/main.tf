resource "aws_efs_file_system" "mealie" {
  creation_token = "${var.project_name}-${var.environment}"
  encrypted      = true

  tags = { Name = "${var.project_name}-${var.environment}-efs" }
}

resource "aws_efs_mount_target" "mealie" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.mealie.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.efs_security_group_id]
}

# Access point scoped to /app/data with Mealie's uid/gid (911)
resource "aws_efs_access_point" "app_data" {
  file_system_id = aws_efs_file_system.mealie.id

  posix_user {
    uid = 911 # Mealie container user 'abc'
    gid = 911
  }

  root_directory {
    path = "/app/data"
    creation_info {
      owner_uid   = 911
      owner_gid   = 911
      permissions = "755"
    }
  }

  tags = { Name = "${var.project_name}-${var.environment}-efs-ap" }
}
