provider "aws" {
  region = var.aws_region
}

##################
#### NETWORK #####
################## 

resource "aws_vpc" "main-vpc" {
	cidr_block = "192.168.0.0/24"
}
resource "aws_subnet" "main-vpc-subnet-1" {
	vpc_id = aws_vpc.main-vpc.id
	cidr_block = "192.168.0.0/28"
	availability_zone = var.aws_az
}
resource "aws_internet_gateway" "main-vpc-subnet-1-igtw" {
	vpc_id = aws_vpc.main-vpc.id
}
resource "aws_route_table" "default_rt" {
	vpc_id = aws_vpc.main-vpc.id	
	route{
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.main-vpc-subnet-1-igtw.id
	}
}
resource "aws_route_table_association" "main-vpc-subnet-1-rt-association" {
	subnet_id = aws_subnet.main-vpc-subnet-1.id
	route_table_id = aws_route_table.default_rt.id
}

##############
#### EC2 #####
##############

resource "aws_eip" "eip" {
        instance = aws_instance.main-server.id
}
resource "aws_instance" "main-server" {
	ami = "ami-0d866da98d63e2b42"
	instance_type = "t2.micro"
	subnet_id = aws_subnet.main-vpc-subnet-1.id
	vpc_security_group_ids = [aws_security_group.main-server-sg.id]
	key_name = "meu-par-de-chaves"
	iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
}
resource "aws_security_group" "main-server-sg" {
	name = "main-server-sg"
	description = "Allow SSH from my IP only & allow HTTP/S from anywhere"
	vpc_id = aws_vpc.main-vpc.id

	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]	
	}

	ingress {
		from_port = 443
		to_port = 443
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]	
	}	

	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = [var.my_ip]
	}

	egress {
		from_port = 0
		to_port = 0
		protocol = -1
		cidr_blocks = ["0.0.0.0/0"]
	}
}

###################################
#### EC2 IAM ROLE & POLICIES ######
###################################

resource "aws_iam_role" "iam_role_for_ec2"{
	name = "ec2_get_presgined_url_role"
	assume_role_policy = jsonencode({
	Version = "2012-10-17",
	Statement = [{
		Effect = "Allow",
		Action = "sts:AssumeRole",
		Principal = {
			Service = "ec2.amazonaws.com"
		}
	}]
})
}
data "aws_iam_policy_document" "ec2_d_policy" {
	statement {
		effect = "Allow"
		actions = ["s3:GetObject", "s3:PutObject"]
		resources = ["arn:aws:s3:::my-bucket-157463745/uploads/*"]
	}
}
data "aws_iam_policy_document" "ec2_second_bucket_policy" {
	statement {
		effect = "Allow"
		actions = ["s3:GetObject"]
		resources = ["arn:aws:s3:::my-bucket-994482384481/processed/*"]
	}
}

resource "aws_iam_policy" "ec2_policy" {
	policy = data.aws_iam_policy_document.ec2_d_policy.json
}
resource "aws_iam_policy" "ec2_second_policy" {
	policy = data.aws_iam_policy_document.ec2_second_bucket_policy.json	
} 

resource "aws_iam_role_policy_attachment" "ec2_policy_attach" {
	role = aws_iam_role.iam_role_for_ec2.name
	policy_arn = aws_iam_policy.ec2_policy.arn
}
resource "aws_iam_role_policy_attachment" "ec2_second_policy_attach" {
	role = aws_iam_role.iam_role_for_ec2.name
	policy_arn = aws_iam_policy.ec2_second_policy.arn
}


resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.iam_role_for_ec2.name
}



##############
##### S3 #####
##############

resource "aws_s3_bucket" "my_bucket" {
	bucket = "my-bucket-157463745"
	force_destroy = true
}

resource "aws_s3_bucket" "second_bucket" {
	bucket = "my-bucket-994482384481"
	force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "my_bucket_lifecycle" {
	bucket = aws_s3_bucket.my_bucket.id
	rule {
		id     = "expire-after-1-day-2"
		status = "Enabled"
		filter {
			prefix = ""
		}
		expiration {
			days = 1
		}
	}
}

resource "aws_s3_bucket_lifecycle_configuration" "second_bucket_lifecycle" {
	bucket = aws_s3_bucket.second_bucket.id
	rule {
		id     = "expire-after-1-day-2"
		status = "Enabled"
		filter {
			prefix = ""
		}
		expiration {
			days = 1
		}
	}
}

resource "aws_s3_bucket_notification" "sns-trigger" {
	bucket = aws_s3_bucket.second_bucket.id
	topic {
		topic_arn = aws_sns_topic.image_processed.arn
		events = ["s3:ObjectCreated:*"]
	}
	depends_on = [aws_sns_topic_policy.allow_second_s3_to_publish_to_sns]
}

resource "aws_s3_bucket_cors_configuration" "my_bucket_cors" {
  bucket = aws_s3_bucket.my_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = ["*"]
  }
}

resource "aws_s3_bucket_cors_configuration" "second_bucket_cors" {
  bucket = aws_s3_bucket.second_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}
###########
###LAMBDA##
###########

resource "aws_lambda_function" "main_function" {
	function_name = "main_function"
	handler       = "index.handler"
        runtime       = "nodejs20.x"
	filename         = "nodejs-image-processing.zip"
	role = aws_iam_role.iam_role_for_lambda.arn
}

resource "aws_iam_role" "iam_role_for_lambda" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

data "aws_iam_policy_document" "second_s3_policy_in_lambda" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::my-bucket-994482384481/processed/*"]
  }
}

data "aws_iam_policy_document" "lambda_permission_for_s3_primary_bucket" {
	statement {
		effect = "Allow"
		actions = ["s3:GetObject"]
		resources = ["arn:aws:s3:::my-bucket-157463745/*"]
	}
}


data "aws_iam_policy_document" "lambda_permission_for_list_s3_primary_bucket" {
	statement {
		effect = "Allow"
		actions = ["s3:ListBucket"]
		resources = ["arn:aws:s3:::my-bucket-157463745"]
	}
}


resource "aws_iam_policy" "policy"{
	policy = data.aws_iam_policy_document.second_s3_policy_in_lambda.json
}
resource "aws_iam_policy" "policy2" {
	policy = data.aws_iam_policy_document.lambda_permission_for_s3_primary_bucket.json
}
resource "aws_iam_policy" "policy3" {
	policy = data.aws_iam_policy_document.lambda_permission_for_list_s3_primary_bucket.json
}


resource "aws_iam_role_policy_attachment" "lambda_policy_in_lambda" {
  role       = aws_iam_role.iam_role_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_second_policy"{
	role = aws_iam_role.iam_role_for_lambda.name
	policy_arn = aws_iam_policy.policy.arn
}
resource "aws_iam_role_policy_attachment" "lambda_third_policy"{
	role = aws_iam_role.iam_role_for_lambda.name
	policy_arn = aws_iam_policy.policy2.arn
}
resource "aws_iam_role_policy_attachment" "lambda_fourth_policy"{
	role = aws_iam_role.iam_role_for_lambda.name
	policy_arn = aws_iam_policy.policy3.arn
}


resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.my_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.my_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.main_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

#######################
#### SNS ##############
#######################

resource "aws_sns_topic" "image_processed" {
  name = "image-processed-topic"
}

resource "aws_sns_topic_policy" "allow_second_s3_to_publish_to_sns" {
  arn    = aws_sns_topic.image_processed.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement: [
      {
        Sid: "AllowS3Publish",
        Effect: "Allow",
        Principal: {
          Service: "s3.amazonaws.com"
        },
        Action: "SNS:Publish",
        Resource: aws_sns_topic.image_processed.arn,
        Condition: {
          ArnLike: {
            "aws:SourceArn": "arn:aws:s3:::my-bucket-994482384481"
          }
        }
      }
    ]
  })
}

#resource "aws_sns_topic_subscription" "ec2_subscriber" {
#  topic_arn = aws_sns_topic.image_processed.arn
#  protocol  = "http"
#  endpoint  = "http://${aws_eip.eip.public_ip}:80/notify"
#}



