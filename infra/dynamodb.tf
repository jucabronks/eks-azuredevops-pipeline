resource "aws_dynamodb_table" "dev_app_data" {
  name           = "dev-app-data"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = "dev"
    Project     = "eks-azuredevops-pipeline"
  }
} 