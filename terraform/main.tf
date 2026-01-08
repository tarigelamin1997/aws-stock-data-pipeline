# 1. Get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 2. Define the Security Group
resource "aws_security_group" "airflow_sg" {
  name        = "airflow-security-group"
  description = "Allow SSH and Airflow Traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- NEW: IAM ROLE CONFIGURATION ---
# 3. Create the Role (The "ID Badge")
resource "aws_iam_role" "airflow_role" {
  name = "airflow_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 4. Give the Role permission to touch S3
resource "aws_iam_role_policy" "airflow_s3_policy" {
  name = "airflow_s3_access"
  role = aws_iam_role.airflow_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

# 5. Create the Profile (To attach the badge to the server)
resource "aws_iam_instance_profile" "airflow_profile" {
  name = "airflow_instance_profile"
  role = aws_iam_role.airflow_role.name
}
# -----------------------------------

# 6. Create the EC2 Instance
resource "aws_instance" "airflow_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = "airflow-prod-key"
  
  # Attach the Security Group
  vpc_security_group_ids = [aws_security_group.airflow_sg.id]
  
  # Attach the NEW IAM Profile
  iam_instance_profile = aws_iam_instance_profile.airflow_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name    = "Airflow-Orchestrator"
    Project = "Portfolio-Phase-1"
  }
}

# 7. The S3 Bucket
resource "aws_s3_bucket" "data_lake" {
  bucket_prefix = "tarig-portfolio-data-lake-" 
  tags = {
    Name    = "Portfolio-Data-Lake"
    Project = "Portfolio-Phase-1"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.data_lake.id
}

# --- PHASE 3: GLUE & ATHENA ---

# 8. Create a Glue Database (The "Folder" for your tables)
resource "aws_glue_catalog_database" "news_db" {
  name = "portfolio_news_db"
}

# 9. IAM Role for Glue (The "ID Badge" for the Crawler)
resource "aws_iam_role" "glue_crawler_role" {
  name = "glue_crawler_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

# 10. Give Glue permission to Read S3 and Write to Data Catalog
resource "aws_iam_role_policy" "glue_policy" {
  name = "glue_s3_policy"
  role = aws_iam_role.glue_crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:*",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# 11. The Glue Crawler (The Robot)
resource "aws_glue_crawler" "news_crawler" {
  database_name = aws_glue_catalog_database.news_db.name
  name          = "portfolio_news_crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/raw_news/"
  }
  
  tags = {
    Project = "Portfolio-Phase-3"
  }
}